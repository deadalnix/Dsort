module sort.bubble;

import std.algorithm;
import std.array;
import std.range;

SortedRange!(Range, less) bubble(alias less = "a < b", Range)(Range r) if(isInputRange!Range) {
	import std.functional;
	alias binaryFun!(less) lessFun;
	
	size_t lastSwap	= -1;
	while(lastSwap > 0) {
		auto current = r.save;
		current.popFront();
		if(current.empty) break;
		
		size_t i		= 0;
		size_t swapPos	= 0;
		foreach(ref a, ref b; lockstep(current, r.save)) {
			if(i > lastSwap) break;
			
			i++;
			if(lessFun(a, b)) {
				swap(a, b);
				
				swapPos = i;
			}
		}
		
		lastSwap = swapPos;
	}
	
	assert(isSorted!less(r));
	
	return assumeSorted!less(r);
}

unittest {
	import std.conv;
	import std.datetime;
	import std.stdio;
	import std.typetuple;
	import std.array;
	
	StopWatch sw = StopWatch(AutoStart.yes);
	
	ulong test(T)(T[] v, string testname) {
		sw.reset();
		bubble(v);
		ulong elapsed = sw.peek().hnsecs;
		
		assert(isSorted(v));
		
		writeln(T.stringof, "\t: ", elapsed, "\t", testname);
		
		return elapsed;
	}
	
	ulong refdruntime(T)(T[] v, string testname) {
		sw.reset();
		sort(v);
		ulong elapsed = sw.peek().hnsecs;
		
		assert(isSorted(v));
		
		writeln(T.stringof, "\t: ", elapsed, "\tReference\t", testname);
		
		return elapsed;
	}
	
	immutable ptrdiff_t[] SIZES = [128, 256, 512, 8192/*, 65536/*, 65536 * 32/*, 65536 * 256*/];
	foreach(S; SIZES) {
		foreach(T; TypeTuple!(ubyte, byte, ushort, short, uint, int, ulong, long)) {
			T[] v;
			v.length = S;
			
			// Little constant value test
			foreach(T b; [T.max, T.min, cast(T) ((T.max + T.min) / 2)]) {
				v[] = b;
				
				test(v, "constants : " ~ to!string(b));
			}
			
			// Already sorted array.
			{
				v[] = T.max;
				
				foreach(b; 0 .. min(S, T.max)) {
					v[b] = cast(T) b;
				}
				
				test(v.dup, "sorted1");
				
				foreach(b; T.min .. min(T.min + S, T.max)) {
					v[b - T.min] = cast(T) b;
				}
				
				test(v, "sorted2");
			}
			
			// Unsorted array
			{
				foreach(b; 0 .. min(S, T.max)) {
					v[S - b - 1] = cast(T) b;
				}
				
				test(v, "unsorted1");
				
				foreach(b; T.min .. min(T.min + S, T.max)) {
					v[S + T.min - b - 1] = cast(T) b;
				}
				
				test(v, "unsorted2");
			}
			
			// Random array
			{
				import std.random;
				Mt19937 gen;
				
				foreach(ref T t; v) {
					static if(T.sizeof < typeof(gen.front).sizeof) {
						t = cast(T) gen.front;
						gen.popFront;
					} else {
						t = ((cast(T) gen.front) << 32);
						gen.popFront;
						
						t |= gen.front;
						gen.popFront;
					}
				}
				
				test(v.dup, "random");
				
				refdruntime(v, "random");
			}
		}
		
		// Random array of floats
		{
			import std.random;
			Mt19937 gen;
	
			float[] v;
			v.length = S;
			
			foreach(ref float t; v) {
				uint tmp = gen.front;
				t = *(cast(float*) &tmp);
				gen.popFront;
			}
			
			test(v.dup, "random");
			
			// refdruntime(v, "random");
		}
	}
}

