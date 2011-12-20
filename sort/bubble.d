module sort.bubble;

import std.algorithm;
import std.functional;

void bubble(alias less = "a < b", T)(T[] datas) {
	alias binaryFun!(less) lessFun;
	
	size_t last = datas.length - 1;
	
	while(last > 0) {
		size_t lastSwap = 0;
		
		foreach(size_t i, ref T current; datas[0 .. last]) {
			if(lessFun(datas[i + 1], current)) {
				swap(current, datas[i + 1]);
				lastSwap = i;
			}
		}
		
		last = lastSwap;
	}
}

unittest {
	import std.conv;
	import std.datetime;
	import std.stdio;
	import std.typetuple;
	
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

