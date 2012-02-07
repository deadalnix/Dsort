module sort.smooth;

import std.algorithm;
import std.range;
import std.array;

// A list of all the Leonardo numbers below 2^32, or 2^64 depending on system
static if(size_t.sizeof == 4) {
	pragma(msg, "32");
	private immutable size_t[] leonardoNumbers = [1, 1, 3, 5, 9, 15, 25, 41, 67, 109, 177, 287, 465, 753, 1219, 1973, 3193, 5167, 8361, 13529, 21891, 35421, 57313, 92735, 150049, 242785, 392835, 635621, 1028457, 1664079, 2692537, 4356617, 7049155, 11405773, 18454929, 29860703, 48315633, 78176337, 126491971, 204668309, 331160281, 535828591, 866988873, 1402817465, 2269806339, 3672623805];
} else static if(size_t.sizeof == 8) {
	private immutable size_t[] leonardoNumbers = [1, 1, 3, 5, 9, 15, 25, 41, 67, 109, 177, 287, 465, 753, 1219, 1973, 3193, 5167, 8361, 13529, 21891, 35421, 57313, 92735, 150049, 242785, 392835, 635621, 1028457, 1664079, 2692537, 4356617, 7049155, 11405773, 18454929, 29860703, 48315633, 78176337, 126491971, 204668309, 331160281, 535828591, 866988873, 1402817465, 2269806339, 3672623805, 5942430145, 9615053951, 15557484097, 25172538049, 40730022147, 65902560197, 106632582345, 172535142543, 279167724889, 451702867433, 730870592323, 1182573459757, 1913444052081, 3096017511839, 5009461563921, 8105479075761, 13114940639683, 21220419715445, 34335360355129, 55555780070575, 89891140425705, 145446920496281, 235338060921987, 380784981418269, 616123042340257, 996908023758527, 1613031066098785, 2609939089857313, 4222970155956099, 6832909245813413, 11055879401769513, 17888788647582927, 28944668049352441, 46833456696935369, 75778124746287811, 122611581443223181, 198389706189510993, 321001287632734175, 519390993822245169, 840392281454979345, 1359783275277224515, 2200175556732203861, 3559958832009428377, 5760134388741632239, 9320093220751060617UL, 15080227609492692857UL];
} else {
	static assert(0, "Unsupported architecture.");
}

unittest {
	foreach(uint i, size_t ln; leonardoNumbers[2 .. $]) {
		assert(ln == (leonardoNumbers[i] + leonardoNumbers[i + 1] + 1));
	}
}

private struct Forest {
	uint forest;
	uint size;
	
	void add() {
		if((forest & 0x03) == 0x03) {
			// Merge last 2 leonardo trees.
			forest = (forest >> 2) | 0x01;
			size += 2;
		} else if(size == 1) {
			// Add leonardo tree lt0.
			forest = (forest << 1) | 0x01;
			size = 0;
		} else {
			// Add leonardo tree lt1.
			forest = (forest << (size - 1)) | 0x01;
			size = 1;
		}
	}
	
	void remove() in {
		assert(size > 1);
	} body {
		forest = ((forest & ~0x01) << 2) | 0x03;
		size -= 2;
	}
	
	void removeTree() in {
		assert(forest > 1);
	} body {
		import core.bitop;
		uint nb0 = bsf(forest & ~0x01);
		
		forest >>= nb0;
		size += nb0;
	}
}

debug {
	private void drawForest(Range)(Range datas) {
		import std.conv;
		import std.stdio;
		Forest forest;
		string[] lines = [""];
		string debugLine = "";
		string sizeLine = "";
		size_t level	= 0;
		size_t maxSize	= 1;
		
		scope(exit) {
			foreach(_; datas) {
				write("********");
			}
			
			writeln();
			
			foreach(line; retro(lines)) {
				writeln(line);
			}
			
			// writeln(debugLine);
			// writeln(sizeLine);
		}
		
		foreach(size_t processed, data; datas) {
			forest.add();
			
			debugLine ~= to!string(level);
			
			if(forest.size < 2) {
				lines[level] ~= to!string(data);
			} else {
				
				if(forest.size == 2) {
					level++;
					debugLine ~= "+";
				} else if(forest.size > 3) {
					level--;
					debugLine ~= "-";
				}
				
				size_t noLine = level + forest.size - 2;
				
				if(lines.length <= noLine) {
					lines.length = noLine + 1;
					
					for(size_t i = 0; i < processed; i++) {
						lines[noLine] ~= "\t";
					}
				}
				
				lines[noLine] ~= to!string(data);
			}
			
			size_t remainingItems = datas.length - processed - 1;
			
			bool isLast = false;
			switch(forest.size) {
				case 1:
					// It is the last element or it is the penultimate element and the previous tree isn't lt2 (no no merge could occur).
					isLast = (remainingItems == 1) && !(forest.forest & 0x02);
				case 0:
					// It is the last element.
					isLast = isLast || (remainingItems == 0);
					break;
				default:
					// If we have enough space to put more than ltn-1 elements, ltn and ltn-1 tree will merge at some point.
					// If both tree are ltn and ltn-1 and one item will be added, this isn't the last tree.
					isLast = !((remainingItems > leonardoNumbers[forest.size - 1]) || ((remainingItems > 0) && ((forest.forest & 0x03) == 0x03)));
			}
			
			if(isLast) {
				// New tree !
				level = 0;
			}
			
			foreach(ref line; lines) {
				line ~= "\t";
			}
			
			debugLine ~= "\t";
			sizeLine ~= to!string(forest.size) ~ "\t";
		}
	}
}

private void rebalanceHeap(alias lessFun, Range)(Range datas, uint size) {
	size_t root = datas.length - 1;
	
	// A tree of size 1 is always balanced because it contains only one element.
	while(size > 1) {
		size_t maxChild		= root - 1;
		uint childSize		= size - 2;
		
		// Test if this child is smaller than the other one, pick the second one.
		size_t otherChild = maxChild - leonardoNumbers[size - 2];
		if(lessFun(datas[maxChild], datas[otherChild])) {
			maxChild	= otherChild;
			childSize	= size - 1;
		}
		
		// If the root is bigger, then we are done.
		if(lessFun(datas[maxChild], datas[root])) return;
		
		// Swap the root and the biggest child and start again from the biggest child.
		swap(datas[maxChild], datas[root]);
		root	= maxChild;
		size	= childSize;
	}
}

private void rectifyForest(alias lessFun, Range)(Range datas, Forest forest) {
	// All tree are correct execpt the first one, which is balanced except the root.
	// We will look for the right tree to put this root in.
	while(true) {
		// If this is the only tree that remain, we are done.
		if(datas.length == leonardoNumbers[forest.size]) break;
		
		size_t root			= datas.length - 1;
		size_t toCompare	= root;
		
		if(forest.size > 1) {
			// The biggest element of this current heap is either the root or one of its child.
			size_t maxChild	= root - 1;
			
			// Test if this child is smaller than the other one, pick the second one.
			size_t otherChild = maxChild - leonardoNumbers[forest.size - 2];
			
			if(lessFun(datas[maxChild], datas[otherChild])) {
				maxChild	= otherChild;
			}
			
			// If one child is bigger than the root, it is the biggest element of the tree. Otherwize, the root is.
			if(lessFun(datas[toCompare], datas[maxChild])) {
				toCompare = maxChild;
			}
		}
		
		// If the biggest element of this tree is bigger than the root of the previous tree, we have find the right tree.
		size_t previousHeap	= root - leonardoNumbers[forest.size];
		if(!lessFun(datas[toCompare], datas[previousHeap])) break;
		
		// The root of previous tree is bigger than all elements of curren tree.
		// Let's put it as a root of current, so the current tree is correct.
		// Then try to reproduce this process to include the current root in the previous tree.
		swap(datas[previousHeap], datas[root]);
		datas = datas[0 .. previousHeap + 1];
		
		forest.removeTree();
	}
	
	// We found the right tree to include the element, we rebalnce that tree to include that element at the right place.
	rebalanceHeap!(lessFun)(datas, forest.size);
}

private void add(alias lessFun, Range)(Range datas, size_t remainingItems, ref Forest forest) {
	forest.add();
	
	bool isLast = false;
	switch(forest.size) {
		case 1:
			// It is the last element or it is the penultimate element and the previous tree isn't lt2 (no no merge could occur).
			isLast = (remainingItems == 1) && !(forest.forest & 0x02);
		case 0:
			// It is the last element.
			isLast = isLast || (remainingItems == 0);
			break;
		default:
			// If we have enough space to put more than ltn-1 elements, ltn and ltn-1 tree will merge at some point.
			// If both tree are ltn and ltn-1 and one item will be added, this isn't the last tree.
			isLast = !((remainingItems > leonardoNumbers[forest.size - 1]) || ((remainingItems > 0) && ((forest.forest & 0x03) == 0x03)));
	}
	
	if(!isLast) {
		rebalanceHeap!lessFun(datas, forest.size);
	} else {
		rectifyForest!lessFun(datas, forest);
	}
}

private void remove(alias lessFun, Range)(Range datas, ref Forest forest) {
	// If the size of the last tree is 0 or 1, then no new tree will be exposed and nothing has to be done.
	if(forest.size < 2) {
		forest.removeTree();
		return;
	}
	
	forest.remove();
	size_t rightHeap	= datas.length - 1;
	
	Forest notLast = forest;
	notLast.removeTree();
	size_t leftHeap	= rightHeap - leonardoNumbers[forest.size];
	
	rectifyForest!lessFun(datas[0 .. leftHeap], notLast);
	rectifyForest!lessFun(datas[0 .. rightHeap], forest);
}

SortedRange!(Range, less) smooth(alias less = "a < b", Range)(Range datas) {
	import std.functional;
	alias binaryFun!less lessFun;
	
	Forest forest;
	
	for(size_t i = 1; i <= datas.length; i++) {
		add!lessFun(datas[0 .. i], datas.length - i, forest);
	}
	
	for(size_t i = datas.length; i > 2; i--) {
		remove!lessFun(datas[0 .. i], forest);
	}
	
	assert(isSorted!less(datas));
	
	return assumeSorted!less(datas);
}

unittest {
	uint[] test = [12, 11, 10, 9, 8, 7, 6, 5, 11, 10, 9, 8, 7, 6, 5, 4, 11, 10, 9, 8, 7, 6, 5, 4, 11, 10, 9, 8, 7, 6, 5, 4, 4, 11, 10, 9, 8, 7, 6, 5, 4, 11, 10, 9, 8, 7, 6, 5, 4, 11, 10, 9, 8, 7, 6, 5, 4, 2, 1];
	smooth(test);
	
	assert(isSorted(test));
	
	// Random array
	{
		import std.random;
		Mt19937 gen;
		
		test.length = 65536 * 32;
		
		foreach(ref uint t; test) {
			t = gen.front;
			gen.popFront;
		}
		
		smooth(test);
		assert(isSorted(test));
	}
}

