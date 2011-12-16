module radix;

import std.algorithm;
import std.traits;
import core.memory;

// By testing this radix isn't interesting if sizeof > 4. I don't really know why, because it supposed to be O(N) anyway.
private immutable uint maxTypeSize = 4;
private void[] buffer = void;
private uint[maxTypeSize * 256] histogram = void;

void clearBuffer() {
	buffer = null;
}

private template requireRadixify(T) {
	enum bool requireRadixify = isFloatingPoint!(T);
}

private enum RadixifyMode {
	DoNothing,
	Radixify,
	RadixifyAndStore,
	UnRadixify,
}

private ubyte[T.sizeof] radixify(T)(ref T data) if(isFloatingPoint!(T)) {
	uint f = *(cast(uint*) &data);
	uint mask = -(f >> 31) | 0x80000000;
	f ^= mask;
	
	return *(cast(ubyte[T.sizeof]*) &f);
}

private T unRadixify(T)(ubyte[T.sizeof] data) if(isFloatingPoint!(T)) {
	uint f = *(cast(uint*) &data);
	uint mask = ((f >> 31) - 1) | 0x80000000;
	f ^= mask;
	
	return *(cast(T*) &f);
}

unittest {
	foreach(float f; [2.0f, 3.0f, 4.0f, -2.0f, 3.141592f, -7.2563f, -2.1f]) {
		assert(unRadixify!float(radixify(f)) == f);
	}
}

private void computeOffsets(uint S)(uint pass, ref ubyte[S][] source, ref ubyte[S][] destination, ref uint[] counters) in {
	assert(pass < S);
} body {
	uint prevcount = counters[0];
	counters[0] = 0;
	foreach(uint i, ref uint count; counters[1 .. $]) {
		uint currcount	= count;
		count			= counters[i] + prevcount;
		prevcount		= currcount;
	}
}

private void computeSignedOffsets(uint S)(uint pass, ref ubyte[S][] source, ref ubyte[S][] destination, ref uint[] counters) in {
	assert(pass < S);
} body {
	uint prevcount = void, currcount = void;
	
	// Negatives values (from 128 to 255) come first.
	prevcount = counters[128];
	counters[128] = 0;
	for(uint i = 128; i < 255; i++) {
		currcount		= counters[i + 1];
		counters[i + 1] = counters[i] + prevcount;
		prevcount		= currcount;
	}
	
	// Positives values (from 0 to 127) comes after negatives.
	currcount	= counters[0];
	counters[0]	= prevcount + counters[255];
	prevcount	= currcount;
	for(uint i = 0; i < 127; i++) {
		currcount		= counters[i + 1];
		counters[i + 1] = counters[i] + prevcount;
		prevcount		= currcount;
	}
}

private uint radixMulitPass(T, alias offsetsCalculator = computeOffsets, RadixifyMode radixifyMode = RadixifyMode.DoNothing)(ref ubyte[T.sizeof][] source, ref ubyte[T.sizeof][] destination, ref uint pass, uint end) in {
	assert(pass < end && end <= T.sizeof);
} body {
	uint nbPasses = 0;
	while(pass < end) {
		uint[] counters = histogram[pass * 256 .. (pass + 1) * 256];
		
		static if(radixifyMode == RadixifyMode.Radixify || radixifyMode == RadixifyMode.RadixifyAndStore) {
			// TODO: report dmd bug if the variable is called radix.
			// TODO: bug repport dmd crash in 1 liner.
			ubyte[T.sizeof] radox = radixify(*(cast(T*) source.ptr));
			bool skip = (counters[radox[pass]] == source.length);
		} else {
			bool skip = (counters[source[0][pass]] == source.length);
		}
		
		// If all sources has the same value for this radix, skip that iterration.
		if(skip) {
			pass++;
			continue;
		}
		
		offsetsCalculator!(T.sizeof)(pass, source, destination, counters);
		
		foreach(uint i, ubyte[T.sizeof] data; source) {
			static if(radixifyMode == RadixifyMode.Radixify) {
				// TODO: bug repport dmd crash in 1 liner.
				ubyte[T.sizeof] radix = radixify(*(cast(T*) data.ptr));
				
				destination[counters[radix[pass]]++] = data;
			} else static if(radixifyMode == RadixifyMode.UnRadixify) {
				// TODO: bug repport dmd crash in 1 liner.
				T radix = unRadixify!T(data);
				
				destination[counters[data[pass]]++] = *(cast(ubyte[T.sizeof]*) &radix);
			} else {
				static if(radixifyMode == RadixifyMode.RadixifyAndStore) {
					data = radixify(*(cast(T*) data.ptr));
				}
				
				destination[counters[data[pass]]++] = data;
			}
		}
		
		swap(source, destination);
		pass++;
		
		static if(radixifyMode == RadixifyMode.DoNothing) {
			nbPasses++;
		} else {
			// We want to run radixify once
			return 1;
		}
	}
	
	return nbPasses;
}

uint radix(T)(T[] datas) if(isNumeric!(T) && (T.sizeof <= maxTypeSize)) in {
	assert(datas.length <= uint.max);
} out {
	assert(isSorted(datas));
} body {
	uint[] histogram = .histogram[0 .. 256 * T.sizeof];
	
	// Create required buffer
	auto dataSize = datas.length * T.sizeof;
	if(buffer.length < dataSize) buffer.length = dataSize;
	
	// Prepare source and destination slices.
	ubyte[T.sizeof][] source		= cast(ubyte[T.sizeof][]) datas;
	ubyte[T.sizeof][] destination	= (cast(ubyte[T.sizeof][]) buffer)[0 .. source.length]; // Buffer can be longer from a previous run of radix, so we slice it.
	
	// Build histograms
	histogram[]	= 0;
	T* prev		= datas.ptr;
	T* p		= datas.ptr;
	T* pe		= p + datas.length;
	while(p < pe) {
		// Check if array is already sorted
		if(*p < *prev) break;
		prev = p;
		
		// Fill histogram
		static if(requireRadixify!(T)) {
			foreach(uint i, ubyte radix; radixify(*p)) {
				histogram[radix + i * 256]++;
			}
		} else {
			foreach(uint i, ubyte radix; *(cast(ubyte[T.sizeof]*) p)) {
				histogram[radix + i * 256]++;
			}
		}
		
		p++;
	}
	
	// If p == pe, then the array is sorted already sorted, as we never breaked.
	if(p == pe) return 0;
	
	// Finish filling histogram without checkign if the array is already sorted.
	while(p < pe) {
		// Fill histogram
		static if(requireRadixify!(T)) {
			foreach(uint i, ubyte radix; radixify(*p)) {
				histogram[radix + i * 256]++;
			}
		} else {
			foreach(uint i, ubyte radix; *(cast(ubyte[T.sizeof]*) p)) {
				histogram[radix + i * 256]++;
			}
		}
		
		p++;
	}
	
	assert(p == pe);
	
	uint nbPasses		= 0;
	uint pass			= 0;
	static if(requireRadixify!(T)) {
		immutable uint end = T.sizeof - 1;
		
		nbPasses += radixMulitPass!(T, computeOffsets, RadixifyMode.RadixifyAndStore)(source, destination, pass, end);
		
		if(pass < end) {
			nbPasses += radixMulitPass!(T, computeOffsets, RadixifyMode.DoNothing)(source, destination, pass, end);
		}
		
		if(nbPasses > 0) {
			// If we have at least one pass, data has to be unradixified.
			uint unRadixifyPass = radixMulitPass!(T, computeOffsets, RadixifyMode.UnRadixify)(source, destination, pass, end + 1);
			
			if(unRadixifyPass == 0) {
				// The unradixification has not been done !
				if((nbPasses % 2) == 0) {
					// Do in place unradixification.
					destination = source;
				}
				
				foreach(uint i, ubyte[T.sizeof] data; source) {
					T radix = unRadixify!T(source[i]);
					destination[i] = *(cast(ubyte[T.sizeof]*) &radix);
				}
			}
			
			nbPasses++;
		} else {
			// If we have 0 passes, then we have to radixify, but do not store the result as we are in the last pass.
			nbPasses += radixMulitPass!(T, computeOffsets, RadixifyMode.Radixify)(source, destination, pass, end + 1);
		}
	} else {
		static if(isSigned!(T)) {
			immutable uint end = T.sizeof - 1;
		} else {
			immutable uint end = T.sizeof;
		}
		
		static if(end > 0) {
			nbPasses += radixMulitPass!(T, computeOffsets, RadixifyMode.DoNothing)(source, destination, pass, end);
		}
		
		// If we have a signed value, then we do an extra pass with different offset computation.
		static if(isSigned!(T)) {
			nbPasses += radixMulitPass!(T, computeSignedOffsets, RadixifyMode.DoNothing)(source, destination, pass, end + 1);
		}
	}
	
	// If an odd number of passes have been done, they we need to copy once more to get an in place sort.
	if(((nbPasses % 2) != 0) && (source.ptr != destination.ptr))  {
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
		ulong elapsed = sw.peek().hnsecs;
		
		assert(isSorted(v));
		
		writeln(T.stringof, "\t: ", elapsed, "\tin ", passes, " passe(s).\t", testname);
		
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
	
	immutable ptrdiff_t[] SIZES = [128, 256, 512, 8192, 65536, 65536 * 32, 65536 * 256];
	foreach(S; SIZES) {
		foreach(T; TypeTuple!(ubyte, byte, ushort, short, uint, int/*, ulong, long*/)) {
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
			
			// TODO: phobos crash on that one, do bug repport.
			// refdruntime(v, "random");
		}
	}
}

