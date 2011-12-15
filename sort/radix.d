module radix;

import std.algorithm;
import std.traits;
import core.memory;

private void[] buffer = void;
private uint[256] offsets = void;
private uint[2048] histogramBuffer = void;

void clearBuffer() {
	buffer = null;
}

private void computeOffsets(uint S)(uint pass, ref ubyte[S][] source, ref ubyte[S][] destination, const ref uint[] counters) in {
	assert(pass < S);
} body {
	offsets[0] = 0;
	foreach(uint i, ref uint offset; offsets[1 .. $]) {
		offset = offsets[i] + counters[i];
	}
}

private void computeSignedOffsets(uint S)(uint pass, ref ubyte[S][] source, ref ubyte[S][] destination, const ref uint[] counters) in {
	assert(pass < S);
} body {
	// Negatives values (from 128 to 255) come first.
	offsets[128] = 0;
	for(uint i = 128; i < 255; i++) {
		offsets[i + 1] = offsets[i] + counters[i];
	}
	
	// Positives values (from 0 to 127) comes after negatives.
	offsets[0] = offsets[255] + counters[255];
	for(uint i = 0; i < 127; i++) {
		offsets[i + 1] = offsets[i] + counters[i];
	}
}

private uint radixMulitPass(uint S, uint A, uint B, alias OffsetsCalculator = computeOffsets)(ref ubyte[S][] source, ref ubyte[S][] destination, uint[] histogram) if(A < B && B <= S) {
	uint nbPasses = 0;
	foreach(pass; A .. B) {
		uint[] counters = histogram[pass * 256 .. (pass + 1) * 256];
		
		// If all sources has the same value for this radix, skip that iterration.
		if(counters[source[0][pass]] == source.length) continue;
		
		OffsetsCalculator!(S)(pass, source, destination, counters);
		
		nbPasses++;
		
		foreach(ubyte[S] data; source) {
			destination[offsets[data[pass]]++] = data;
		}
		
		swap(source, destination);
	}
	
	return nbPasses;
}

uint radix(T)(T[] datas) if(isIntegral!(T) && (T.sizeof <= 8)) in {
	assert(datas.length <= uint.max);
} out{
	assert(isSorted(datas));
} body {
	uint[] histogram = histogramBuffer[0 .. 256 * T.sizeof];
	
	// Create required buffer
	auto dataSize = datas.length * T.sizeof;
	if(buffer.length < dataSize) buffer.length = dataSize;
	
	// Prepare source and destination slices.
	ubyte[T.sizeof][] source		= cast(ubyte[T.sizeof][]) datas;
	ubyte[T.sizeof][] destination	= (cast(ubyte[T.sizeof][]) buffer)[0 .. source.length];
	
	// Build histograms
	histogram[]			= 0;
	T prev				= datas[0];
	ubyte[T.sizeof]* p	= source.ptr;
	ubyte[T.sizeof]* pe	= p + source.length;
	while(p < pe) {
		ubyte[T.sizeof] rawdata = *p;
		
		// Check if array is already sorted
		T current = *(cast(T*) rawdata.ptr);
		if(current < prev) break;
		prev = current;
		
		// Fill histogram
		foreach(uint i, ubyte radix; rawdata) {
			histogram[radix + i * 256]++;
		}
		
		p++;
	}
	
	// If p == pe, then the array is sorted already sorted, as we never breaked.
	if(p == pe) return 0;
	
	// Finish filling histogram without checkign if the array is already sorted.
	while(p < pe) {
		ubyte[T.sizeof] rawdata = *p;
		
		// Fill histogram
		foreach(uint i, ubyte radix; rawdata) {
			histogram[radix + i * 256]++;
		}
		
		p++;
	}
	
	assert(p == pe);
	
	uint nbPasses;
	static if(isUnsigned!(T)) {
		nbPasses = radixMulitPass!(T.sizeof, 0, T.sizeof)(source, destination, histogram);
	} else {
		static if(T.sizeof > 1) {
			nbPasses = radixMulitPass!(T.sizeof, 0, T.sizeof - 1)(source, destination, histogram);
		}
		
		nbPasses += radixMulitPass!(T.sizeof, T.sizeof - 1, T.sizeof, computeSignedOffsets)(source, destination, histogram);
	}
	
	// If an odd number of passes have been done, they we need to copy once more to get an in place sort.
	if((nbPasses % 2) != 0)  {
		destination[] = source;
		nbPasses++;
	}
	
	// Each counted pass + the first one to init histograms
	return nbPasses + 1;
}

unittest {
	import std.conv;
	import std.datetime;
	import std.stdio;
	import std.typetuple;
	
	StopWatch sw = StopWatch(AutoStart.yes);
	
	ulong test(T)(T[] v, string testname) {
		sw.reset();
		uint passes = radix(v);
		ulong elapsed = sw.peek().nsecs;
		
		assert(isSorted(v));
		
		writeln(T.stringof, "\t: ", elapsed, "\tin ", passes, " passe(s).\t", testname);
		
		return elapsed;
	}
	
	foreach(S; [128, 256, 512, 8192, 65536, 65536 * 32]) {
		foreach(T; TypeTuple!(ubyte, byte, ushort, short, uint, int, ulong, long)) {
			// Prepare buffer
			if(buffer.length < S * T.sizeof) {
				clearBuffer();
				buffer.length = S * T.sizeof;
			}
			
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
				
				test(v, "sorted1");
				
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
				
				test(v, "random");
			}
		}
	}
}

