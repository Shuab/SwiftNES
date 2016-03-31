//
//  CPU.swift
//  SimpleNES
//
//  Created by Adam Gastineau on 3/23/16.
//  Copyright © 2016 Adam Gastineau. All rights reserved.
//

import Foundation

class CPU: NSObject {

	// MARK: Registers

	/**
	 Lower Half of PC
	*/
	var PCL: UInt8;

	/**
	 Upper Half of PC
	*/
	var PCH: UInt8;

	/**
	 Stack Pointer
	*/
	var SP: UInt8;

	/**
	 Processor Status
	*/
	var P: UInt8;

	/**
	 Accumulator
	*/
	var A: UInt8;

	/**
	 Index Register X
	*/
	var X: UInt8;

	/**
	 Index Register Y
	*/
	var Y: UInt8;

	var mainMemory: Memory;
    var ppuMemory: Memory;
    
    enum AddressingMode {
        case Accumulator
        
        case Implied
        
        case Immediate
        
        case Absolute
        case AbsoluteIndexedX
        case AbsoluteIndexedY
        
        /**
         For JMP only
         */
        case AbsoluteIndirect
        
        case ZeroPage
        case ZeroPageIndexedX
        case ZeroPageIndexedY
        
        case IndirectX
        case IndirectY
        
        case Relative
    }

	/**
	 Initializes the CPU
	*/
    init(mainMemory: Memory, ppuMemory: Memory) {
		self.PCL = 0;
		self.PCH = 0;

		self.SP = 0;

		self.P = 0;

		self.A = 0;
		self.X = 0;
		self.Y = 0;
		
		self.mainMemory = mainMemory;
        self.ppuMemory = ppuMemory;
    }
    
    func reset() {
        // Load program start address from RESET vector (0xFFFC)
        let programStartAddress = self.mainMemory.readTwoBytesMemory(0xFFFC);
        
        // Set PC to program start address
        setPC(programStartAddress);
        
        print("PC initialized to \((UInt16(self.PCH) << 8) | UInt16(self.PCL))");
    }

	/**
	 Executes one CPU cycle
	*/
	func step() {
		
	}
    
    func address(lower:UInt8, upper:UInt8) -> Int {
        return Int(lower) | (Int(upper) << 8);
    }
    
    func setPBit(index: Int, value: Bool) {
        let bit: UInt8 = value ? 0xFF : 0;
        self.P ^= (bit ^ self.P) & (1 << UInt8(index));
    }
    
    func getPBit(index: Int) -> Bool {
        return ((self.P >> UInt8(index)) & 0x1) == 1;
    }
    
    func readFromMemoryUsingAddressingMode(mode: AddressingMode) -> UInt8 {
        switch mode {
        case .Immediate:
            return fetchPC();
        default: break
        }
        
        return self.mainMemory.readMemory(addressUsingAddressingMode(mode));
    }
    
    func addressUsingAddressingMode(mode: AddressingMode) -> Int {
        switch mode {
        case AddressingMode.ZeroPage:
            return Int(fetchPC());
            
        case AddressingMode.ZeroPageIndexedX, .ZeroPageIndexedY:
            var index = self.X;
            
            if(mode == AddressingMode.ZeroPageIndexedY) {
                index = self.Y;
            }
            
            return Int((fetchPC() + index) & 0xFF);
            
        case AddressingMode.Absolute:
            let lowByte = fetchPC();
            let highByte = fetchPC();
            
            return address(lowByte, upper: highByte);
            
        case AddressingMode.AbsoluteIndexedX, .AbsoluteIndexedY:
            let lowByte = fetchPC();
            let highByte = fetchPC();
            
            var index = self.X;
            
            if(mode == AddressingMode.AbsoluteIndexedY) {
                index = self.Y;
            }
            
            let originalAddress = address(lowByte, upper: highByte);
            
            return Int((UInt16(originalAddress) + UInt16(index)) & 0xFFFF);
            
        case AddressingMode.IndirectX:
            let immediate = fetchPC();
            
            let lowByte = self.mainMemory.readMemory(Int((immediate + self.X) & 0xFF));
            let highByte = self.mainMemory.readMemory(Int((immediate + self.X + 1) & 0xFF));
            
            return address(lowByte, upper: highByte);
            
        case AddressingMode.IndirectY:
            let immediate = fetchPC();
            
            let lowByte = self.mainMemory.readMemory(Int(immediate));
            let highByte = self.mainMemory.readMemory(Int(UInt8((immediate + 1) & 0xFF)));
            
            let originalAddress = address(lowByte, upper: highByte);
            
            return Int((UInt16(originalAddress) + UInt16(self.Y)) & 0xFFFF);
            
        default:
            print("Invalid AddressingMode on addressUsingAddressingMode");
            return 0;
        }
    }
	
	/**
	 Converts the given value to binary coded decimal, where
	 the first nibble is a tens place digit, and the second a
	 ones place digit
	*/
	func bcdValue(value: UInt8) -> UInt8 {
		let upper = (value >> 4) & 0xF;
		let lower = value & 0xF;
		
		return upper * 10 + lower;
	}
    
    // MARK: - PC Operations
    func setPC(address: UInt16) {
        self.PCL = UInt8(address & 0xFF);
        self.PCH = UInt8((address & 0xFF00) >> 8);
    }
    
    func getPC() -> UInt16 {
        return UInt16(self.PCL) | (UInt16(self.PCH) << 8);
    }
    
    func incrementPC() {
        setPC(getPC() + 1);
    }
    
    func decrementPC() {
        setPC(getPC() - 1);
    }
    
    func fetchPC() -> UInt8 {
        let byte = self.mainMemory.readMemory(Int(getPC()));
        
        incrementPC();
        
        return byte;
    }
    
    // MARK: - Stack Operations
    func push(byte: UInt8) {
        self.mainMemory.writeMemory(0x100 + Int(self.SP), data: byte);
        
        if(self.SP == 0xFF) {
            print("ERROR: Stack overflow");
        }
        
        self.SP = self.SP + 1;
    }
    
    func pop() -> UInt8 {
        if(self.SP == 0) {
            print("ERROR: Stack underflow");
        }
        
        self.SP = self.SP - 1;
        
        return self.mainMemory.readMemory(0x100 + Int(self.SP));
    }
    
    // MARK: - Instructions
    // MARK: Stack
    
    /**
     Simulate Interrupt ReQuest (IRQ)
    */
    func BRK() -> Int {
        push(self.PCH);
        push(self.PCL);
        push(self.P | 0x10);
        
        self.PCL = self.mainMemory.readMemory(0xFFFE);
        self.PCH = self.mainMemory.readMemory(0xFFFF);
        
        return 7;
    }
    
    /**
     ReTurn from Interrupt
    */
    func RTI() -> Int {
        self.P = pop();
        self.PCL = pop();
        self.PCH = pop();
        
        return 6;
    }
    
    /**
     ReTurn from Subroutine
    */
    func RTS() -> Int {
        self.PCL = pop();
        self.PCH = pop();
        
        incrementPC();
        
        return 6;
    }
    
    /**
     PusH A
    */
    func PHA() -> Int {
        push(self.A);
        
        return 3;
    }
    
    /**
     PusH P
    */
    func PHP() -> Int {
        push(self.P);
        
        return 3;
    }
    
    /**
     PulL from Stack to A
    */
    func PLA() -> Int {
        self.A = pop();
        
        return 4;
    }
    
    /**
     PulL from Stack to P
    */
    func PLP() -> Int {
        self.P = pop();
        
        return 4;
    }
    
    /**
     Jump to SubRoutine
    */
    func JSR() -> Int {
        let lowByte = fetchPC();
        
        // TODO: Possibly incorrect?
        push(self.PCH);
        push(self.PCL);
        
        self.PCL = lowByte;
        self.PCH = fetchPC();
        
        return 6;
    }
	
	// MARK: Memory
	
	/**
	 Store A in Memory
	*/
	func STA(mode: AddressingMode) -> Int {
		var length = 5;
		
		switch mode {
			case .ZeroPage:
				length = 3;
				
			case .ZeroPageIndexedX, .Absolute:
				length = 4;
				
			case .AbsoluteIndexedX, .AbsoluteIndexedY:
				length = 5;
			
			case .IndirectX, .IndirectY:
				length = 6;
			
			default:
				print("Invalid AddressingMode on STA");
				return -1;
		}
		
		let address = addressUsingAddressingMode(mode);
		
		self.mainMemory.writeMemory(address, data: self.A);
		
		return length;
	}
	
	/**
	 Store X in Memory
	*/
	func STX(mode: AddressingMode) -> Int {
		var length = 4;
		
		switch mode {
			case .ZeroPage:
				length = 3;
				
			case .ZeroPageIndexedY, .Absolute:
				length = 4;
				
			default:
				print("Invalid AddressingMode on STX");
				return -1;
		}
		
		let address = addressUsingAddressingMode(mode);
		
		self.mainMemory.writeMemory(address, data: self.X);
		
		return length;
	}
	
	/**
	 Store Y in Memory
	*/
	func STY(mode: AddressingMode) -> Int {
		var length = 4;
		
		switch mode {
		case .ZeroPage:
			length = 3;
			
		case .ZeroPageIndexedX, .Absolute:
			length = 4;
			
		default:
			print("Invalid AddressingMode on STY");
			return -1;
		}
		
		let address = addressUsingAddressingMode(mode);
		
		self.mainMemory.writeMemory(address, data: self.Y);
		
		return length;
	}
	
	/**
	 Load A from Memory
	*/
	func LDA(mode: AddressingMode) -> Int {
		switch mode {
			case .Immediate, .ZeroPage, .ZeroPageIndexedX,
				 .Absolute, .AbsoluteIndexedX, .AbsoluteIndexedY,
				 .IndirectX, .IndirectY:
				return LOAD(mode, register: &self.A);
		default:
			print("Invalid AddressingMode on LDA");
		}
		
		return -1;
	}
	
	/**
	 Load X from Memory
	*/
	func LDX(mode: AddressingMode) -> Int {
		switch mode {
			case .Immediate, .ZeroPage, .ZeroPageIndexedY,
				 .Absolute, .AbsoluteIndexedY:
				return LOAD(mode, register: &self.X);
		default:
			print("Invalid AddressingMode on LDX");
		}
		
		return -1;
	}
	
	/**
	 Load Y from Memory
	*/
	func LDY(mode: AddressingMode) -> Int {
		switch mode {
			case .Immediate, .ZeroPage, .ZeroPageIndexedX,
				 .Absolute, .AbsoluteIndexedX:
				return LOAD(mode, register: &self.Y);
		default:
			print("Invalid AddressingMode on LDY");
		}
		
		return -1;
	}
	
	/**
	Internal handler for LDA, LDX, LDY
	*/
	func LOAD(mode: AddressingMode, register: UnsafeMutablePointer<UInt8>) -> Int {
		var length = 4;
		
		switch mode {
			case AddressingMode.Immediate:
				length = 2;
				
			case AddressingMode.ZeroPage:
				length = 3;
				
			case AddressingMode.IndirectX:
				length = 6;
				
			case AddressingMode.IndirectY:
				length = 5;
				
			case AddressingMode.ZeroPageIndexedX, .ZeroPageIndexedY,
				 .Absolute, .AbsoluteIndexedX, .AbsoluteIndexedY:
				length = 4;
				
			default:
				print("Invalid AddressingMode on LOAD");
				return -1;
		}
		
		register.memory = readFromMemoryUsingAddressingMode(mode);
		
		// Set negative flag
		setPBit(7, value: (self.A >> 8) == 1);
		
		// Set zero flag
		setPBit(1, value: (self.A == 0));
		
		return length;
	}
	
	/**
	 Transfer A to X
	*/
	func TAX() -> Int {
		self.X = self.A;
		
		// Set negative flag
		setPBit(7, value: (self.X >> 8) == 1);
		
		// Set zero flag
		setPBit(1, value: (self.X == 0));
	}
	
	/**
	 Transfer A to Y
	*/
	func TAY() -> Int {
		self.Y = self.A;
		
		// Set negative flag
		setPBit(7, value: (self.Y >> 8) == 1);
		
		// Set zero flag
		setPBit(1, value: (self.Y == 0));
	}
	
	/**
	 Transfer Stack Pointer to X
	*/
	func TSX() -> Int {
		self.X = self.SP;
		
		// Set negative flag
		setPBit(7, value: (self.X >> 8) == 1);
		
		// Set zero flag
		setPBit(1, value: (self.X == 0));
	}
	
	/**
	 Transfer X to A
	*/
	func TXA() -> Int {
		self.A = self.X;
		
		// Set negative flag
		setPBit(7, value: (self.A >> 8) == 1);
		
		// Set zero flag
		setPBit(1, value: (self.A == 0));
	}
	
	/**
	 Transfer X to SP
	*/
	func TXS() -> Int {
		self.SP = self.X;
		
		// Set negative flag
		setPBit(7, value: (self.SP >> 8) == 1);
		
		// Set zero flag
		setPBit(1, value: (self.SP == 0));
	}
	
	/**
	 Transfer Y to A
	*/
	func TYA() -> Int {
		self.A = self.Y;
		
		// Set negative flag
		setPBit(7, value: (self.A >> 8) == 1);
		
		// Set zero flag
		setPBit(1, value: (self.A == 0));
	}
	
    /**
     JuMP
    */
    func JMP(mode: AddressingMode) -> Int {
        switch mode {
            case AddressingMode.Absolute:
                let lowByte = fetchPC();
				
                self.PCH = fetchPC();
                self.PCL = lowByte;
            case AddressingMode.AbsoluteIndirect:
                let zeroPageAddress = fetchPC();
				
                self.PCL = self.mainMemory.readMemory(Int(zeroPageAddress));
                self.PCH = self.mainMemory.readMemory(Int(zeroPageAddress) + 1);
            default:
                print("Invalid AddressingMode on JMP");
        }
        
        return 3;
    }
	
    // MARK: Math
    
    /**
     Add Memory to A with Carry
    */
    func ADC(mode: AddressingMode) -> Int {
		var length = 4;
		
		switch mode {
			case .Immediate:
				length = 2;
			
			case .ZeroPage:
				length = 3;
				
			case .ZeroPageIndexedX, .Absolute, .AbsoluteIndexedX, .AbsoluteIndexedY:
				length = 4;
				
			case .IndirectX:
				length = 6;
			
			case .IndirectY:
				length = 5;
			
			default:
				print("Invalid AddressingMode on ADC");
				return -1;
		}
		
		let memoryValue = readFromMemoryUsingAddressingMode(mode);
		
		var temp = UInt16(self.A) + UInt16(memoryValue) + (getPBit(0) ? 1 : 0);
		
		// Set overflow flag
		setPBit(6, value: ((self.A >> 7) & 0x1) != UInt8((temp >> 7) & 0x1))
		
		// Set negative flag
		setPBit(7, value: ((self.A >> 7) & 0x1) == 1);
		
		// Set zero flag
		setPBit(1, value: temp == 0);
		
		// Decimal flag
		if(getPBit(3)) {
			temp = UInt16(bcdValue(self.A)) + UInt16(bcdValue(memoryValue)) + (getPBit(0) ? 1 : 0);
			
			// Set carry flag
			setPBit(0, value: temp > 99);
		} else {
			// Set carry flag
			setPBit(0, value: temp > 255);
		}
		
		self.A = UInt8(temp & 0xFF);
		
		return length;
    }
    
    /**
     Subtract Memory to A with Borrow
    */
    func SBC(mode: AddressingMode) -> Int {
		var length = 4;
		
		switch mode {
			case .Immediate:
				length = 2;
				
			case .ZeroPage:
				length = 3;
				
			case .ZeroPageIndexedX, .Absolute, .AbsoluteIndexedX, .AbsoluteIndexedY:
				length = 4;
				
			case .IndirectX:
				length = 6;
				
			case .IndirectY:
				length = 5;
				
			default:
				print("Invalid AddressingMode on SBC");
				return -1;
		}
		
		let memoryValue = readFromMemoryUsingAddressingMode(mode);
		
		var temp: Int;
		
		// Decimal flag
		if(getPBit(3)) {
			temp = Int(bcdValue(self.A)) - Int(bcdValue(memoryValue)) - (getPBit(0) ? 0 : 1);
			
			// Set overflow flag
			setPBit(6, value: (temp > 99) || (temp < 0));
		} else {
			temp = Int(self.A) - Int(memoryValue) - (getPBit(0) ? 0 : 1);
			
			// Set overflow flag
			setPBit(6, value: (temp > 127) || (temp < -128));
		}
		
		// Set carry flag
		setPBit(0, value: temp >= 0);
		
		// Set negative flag
		setPBit(7, value: ((temp >> 7) & 0x1) == 1);
		
		// Set zero flag
		setPBit(1, value: temp == 0);
		
		self.A = UInt8(temp & 0xFF);
		
        return length;
    }
	
	/**
	 Increment Memory
	*/
	func INC(mode: AddressingMode) -> Int {
		var length = 6;
		
		switch mode {
			case .ZeroPage:
				length = 5;
			
			case .ZeroPageIndexedX, .Absolute:
				length = 6;
			
			case .AbsoluteIndexedX:
				length = 7;
			
			default:
				print("Invalid AddressingMode on INC");
				return -1;
		}
		
		let address = addressUsingAddressingMode(mode);
		var value = self.mainMemory.readMemory(address);
		
		value = value + 1;
		
		// Set negative flag
		setPBit(7, value: (value >> 8) == 1);
		
		// Set zero flag
		setPBit(1, value: (value == 0));
		
		self.mainMemory.writeMemory(address, data: value);
		
		return length;
	}
	
	/**
	 Increment X
	*/
	func INX() -> Int {
		self.X = self.X + 1;
		
		// Set negative flag
		setPBit(7, value: (self.X >> 8) == 1);
		
		// Set zero flag
		setPBit(1, value: (self.X == 0));
		
		return 2;
	}
	
	/**
	Increment Y
	*/
	func INY() -> Int {
		self.Y = self.Y + 1;
		
		// Set negative flag
		setPBit(7, value: (self.Y >> 8) == 1);
		
		// Set zero flag
		setPBit(1, value: (self.Y == 0));
		
		return 2;
	}
	
	/**
	 Decrement Memory
	*/
	func DEC(mode: AddressingMode) -> Int {
		var length = 6;
		
		switch mode {
		case .ZeroPage:
			length = 5;
			
		case .ZeroPageIndexedX, .Absolute:
			length = 6;
			
		case .AbsoluteIndexedX:
			length = 7;
			
		default:
			print("Invalid AddressingMode on DEC");
			return -1;
		}
		
		let address = addressUsingAddressingMode(mode);
		var value = self.mainMemory.readMemory(address);
		
		value = value - 1;
		
		// Set negative flag
		setPBit(7, value: (value >> 8) == 1);
		
		// Set zero flag
		setPBit(1, value: (value == 0));
		
		self.mainMemory.writeMemory(address, data: value);
		
		return length;
	}
	
	/**
	 Decrement X
	*/
	func DEX() -> Int {
		self.X = self.X - 1;
		
		// Set negative flag
		setPBit(7, value: (self.X >> 8) == 1);
		
		// Set zero flag
		setPBit(1, value: (self.X == 0));
		
		return 2;
	}
	
	/**
	 Decrement Y
	*/
	func DEY() -> Int {
		self.Y = self.Y - 1;
		
		// Set negative flag
		setPBit(7, value: (self.Y >> 8) == 1);
		
		// Set zero flag
		setPBit(1, value: (self.Y == 0));
		
		return 2;
	}
	
    /**
     Arithmetic Shift Left
    */
    func ASL(mode: AddressingMode) -> Int {
        var length = 6;
        
        switch mode {
            case .Accumulator:
                length = 2;
            
            case .ZeroPage:
                length = 5;
                
            case .ZeroPageIndexedX, .Absolute:
                length = 6;
                
            case .AbsoluteIndexedX:
                length = 7;
                
            default:
                print("Invalid AddressingMode on ASL");
                return -1;
        }
        
        if(mode == .Accumulator) {
            // Set carry flag
            setPBit(0, value: (self.A >> 8) == 1);
            
            self.A = (self.A << 1) & 0xFE;
            
            // Set negative flag
            setPBit(7, value: (self.A >> 8) == 1);
            
            // Set zero flag
            setPBit(1, value: (self.A == 0));
        } else {
            let address = addressUsingAddressingMode(mode);
            let value = self.mainMemory.readMemory(address);
            
            // Set carry flag
            setPBit(0, value: (value >> 8) == 1);
            
            let temp = (value << 1) & 0xFE;
            
            // Set negative flag
            setPBit(7, value: (temp >> 8) == 1);
            
            // Set zero flag
            setPBit(1, value: (temp == 0));
            
            self.mainMemory.writeMemory(address, data: temp);
        }
        
        return length;
    }
    
    /**
     Logical Shift Right
    */
    func LSR(mode: AddressingMode) -> Int {
        var length = 6;
        
        switch mode {
            case .Accumulator:
                length = 2;
                
            case .ZeroPage:
                length = 5;
                
            case .ZeroPageIndexedX, .Absolute:
                length = 6;
                
            case .AbsoluteIndexedX:
                length = 7;
                
            default:
                print("Invalid AddressingMode on LSR");
                return -1;
        }
        
        if(mode == .Accumulator) {
            // Set negative flag
            setPBit(7, value: false);
            
            // Set carry flag
            setPBit(0, value: (self.A & 0x1) == 1);
            
            self.A = (self.A >> 1) & 0x7F;
            
            // Set zero flag
            setPBit(1, value: (self.A == 0));
        } else {
            let address = addressUsingAddressingMode(mode);
            let value = self.mainMemory.readMemory(address);
            
            // Set negative flag
            setPBit(7, value: false);
            
            // Set carry flag
            setPBit(0, value: (self.A & 0x1) == 1);
            
            let temp = (value >> 1) & 0x7F;
            
            // Set zero flag
            setPBit(1, value: (temp == 0));
            
            self.mainMemory.writeMemory(address, data: temp);
        }
        
        return length;
    }
    
    /**
     ROtate Left
    */
    func ROL(mode: AddressingMode) -> Int {
        var length = 6;
        
        switch mode {
            case .Accumulator:
                length = 2;
                
            case .ZeroPage:
                length = 5;
                
            case .ZeroPageIndexedX, .Absolute:
                length = 6;
                
            case .AbsoluteIndexedX:
                length = 7;
                
            default:
                print("Invalid AddressingMode on ROL");
                return -1;
        }
        
        if(mode == .Accumulator) {
            let carry = (self.A >> 8) & 0x1;
            
            self.A = (self.A << 1) & 0xFE;
            self.A = self.A | (getPBit(0) ? 1:0);
			
			// Set carry flag
			setPBit(0, value: carry == 1);
			
			// Set zero flag
			setPBit(1, value: (self.A == 0));
			
            // Set negative flag
            setPBit(7, value: (self.A >> 8) & 0x1 == 1);
        } else {
            let address = addressUsingAddressingMode(mode);
            var value = self.mainMemory.readMemory(address);
			
			let carry = (value >> 8) & 0x1;
			value = (value << 1) & 0xFE;
			value = value | (getPBit(0) ? 1:0);
            
			// Set carry flag
			setPBit(0, value: carry == 1);
			
			// Set zero flag
			setPBit(1, value: (value == 0));
			
			// Set negative flag
			setPBit(7, value: (value >> 8) & 0x1 == 1);
			
            self.mainMemory.writeMemory(address, data: value);
        }
        
        return length;
    }
	
	/**
	ROtate Right
	*/
	func ROR(mode: AddressingMode) -> Int {
		var length = 6;
		
		switch mode {
		case .Accumulator:
			length = 2;
			
		case .ZeroPage:
			length = 5;
			
		case .ZeroPageIndexedX, .Absolute:
			length = 6;
			
		case .AbsoluteIndexedX:
			length = 7;
			
		default:
			print("Invalid AddressingMode on ROR");
			return -1;
		}
		
		if(mode == .Accumulator) {
			let carry = self.A & 0x1;
			
			self.A = (self.A >> 1) & 0x7F;
			self.A = self.A | (getPBit(0) ? 0x80 : 0);
			
			// Set carry flag
			setPBit(0, value: carry == 1);
			
			// Set zero flag
			setPBit(1, value: (self.A == 0));
			
			// Set negative flag
			setPBit(7, value: (self.A >> 8) & 0x1 == 1);
		} else {
			let address = addressUsingAddressingMode(mode);
			var value = self.mainMemory.readMemory(address);
			
			let carry = value & 0x1;
			value = (value >> 1) & 0x7F;
			value = value | (getPBit(0) ? 0x80 : 0);
			
			// Set carry flag
			setPBit(0, value: carry == 1);
			
			// Set zero flag
			setPBit(1, value: (value == 0));
			
			// Set negative flag
			setPBit(7, value: (value >> 8) & 0x1 == 1);
			
			self.mainMemory.writeMemory(address, data: value);
		}
		
		return length;
	}
	
    // MARK: Logical
	
    /**
     Bitwise XOR A with Memory
    */
    func EOR(mode: AddressingMode) -> Int {
        var length = 4;
		
        switch mode {
            case .Immediate:
                length = 2;
			
            case .ZeroPage:
                length = 3;
			
            case .ZeroPageIndexedX, .Absolute, .AbsoluteIndexedX,
                 .AbsoluteIndexedY:
                length = 4;
            
            case .IndirectX:
                length = 6;
            
            case .IndirectY:
                length = 5;
            
            default:
                print("Invalid AddressingMode on EOR");
                return -1;
        }
        
        self.A = self.A ^ readFromMemoryUsingAddressingMode(mode);
        
        // Set negative flag
        setPBit(7, value: (self.A >> 8) == 1);
        
        // Set zero flag
        setPBit(1, value: (self.A == 0));
        
        return length;
    }
    
    /**
     Bitwise AND A with Memory
    */
    func AND(mode: AddressingMode) -> Int {
        var length = 4;
        
        switch mode {
            case .Immediate, .ZeroPage:
                length = 2;
            
            case .ZeroPageIndexedX:
                length = 3;
            
            case .Absolute, .AbsoluteIndexedX, .AbsoluteIndexedY:
                length = 4;
            
            case .IndirectX:
                length = 6;
            
            case .IndirectY:
                length = 5;
            
            default:
                print("Invalid AddressingMode on AND");
                return -1;
        }
        
        self.A = self.A & readFromMemoryUsingAddressingMode(mode);
        
        // Set negative flag
        setPBit(7, value: (self.A >> 8) == 1);
        
        // Set zero flag
        setPBit(1, value: (self.A == 0));
        
        return length;
    }
    
    /**
     Bitwise OR A with Memory
    */
    func ORA(mode: AddressingMode) -> Int {
        var length = 4;
        
        switch mode {
            case .Immediate, .ZeroPage:
                length = 2;
                
            case .ZeroPageIndexedX:
                length = 3;
                
            case .Absolute, .AbsoluteIndexedX, .AbsoluteIndexedY:
                length = 4;
                
            case .IndirectX:
                length = 6;
                
            case .IndirectY:
                length = 5;
                
            default:
                print("Invalid AddressingMode on ORA");
                return -1;
        }
        
        self.A = self.A | readFromMemoryUsingAddressingMode(mode);
        
        // Set negative flag
        setPBit(7, value: (self.A >> 8) == 1);
        
        // Set zero flag
        setPBit(1, value: (self.A == 0));
        
        return length;
    }
    
    // MARK: Flow Control
    
    /**
     Compare A with Memory
    */
    func CMP(mode: AddressingMode) -> Int {
        var length = 4;
        
        switch mode {
            case .Immediate:
                length = 2;
            
            case .ZeroPage:
                length = 3;
            
            case .ZeroPageIndexedX, .Absolute, .AbsoluteIndexedX, .AbsoluteIndexedY:
                length = 4;
                
            case .IndirectX:
                length = 6;
                
            case .IndirectY:
                length = 5;
                
            default:
                print("Invalid AddressingMode on CMP");
                return -1;
        }
        
        let mem = readFromMemoryUsingAddressingMode(mode);
        let temp = self.A - mem;
        
        // Set negative flag
        setPBit(7, value: (temp >> 8) == 1);
        
        // Set zero flag
        setPBit(1, value: (temp == 0));
        
        // Set carry flag
        setPBit(0, value: (self.A >= mem));
        
        return length;
    }
    
    /**
     Test bits in A with Memory
    */
    func BIT(mode: AddressingMode) -> Int {
        var length = 3;
        
        switch mode {
			case .ZeroPage:
				length = 3;
				
			case .Absolute:
				length = 4;
				
			default:
				print("Invalid AddressingMode on BIT");
				return -1;
        }
        
        let mem = readFromMemoryUsingAddressingMode(mode);
        let temp = self.A & mem;
        
        // Set negative flag
        setPBit(7, value: (temp >> 8) == 1);
        
        // Set overflow flag
        setPBit(6, value: (temp >> 7) == 1);
        
        // Set zero flag
        setPBit(1, value: (temp == 0));
        
        return length;
    }
	
	/**
	 Branch if Carry flag is Clear
	*/
	func BCC() -> Int {
		if(!getPBit(0)) {
			setPC(getPC() + UInt16(fetchPC()));
			return 3;
		}
		
		return 2;
	}
	
	/**
	 Branch if Carry flag is Set
	*/
	func BCS() -> Int {
		if(getPBit(0)) {
			setPC(getPC() + UInt16(fetchPC()));
			return 3;
		}
		
		return 2;
	}
	
	/**
	 Branch if Zero flag is Set
	*/
	func BZS() -> Int {
		if(getPBit(1)) {
			setPC(getPC() + UInt16(fetchPC()));
			return 3;
		}
		
		return 2;
	}
	
	/**
	 Branch if negative flag is set
	*/
	func BMI() -> Int {
		if(getPBit(7)) {
			setPC(getPC() + UInt16(fetchPC()));
			return 3;
		}
		
		return 2;
	}
	
	/**
	 Branch if zero flag is clear
	*/
	func BNE() -> Int {
		if(!getPBit(1)) {
			setPC(getPC() + UInt16(fetchPC()));
			return 3;
		}
		
		return 2;
	}
	
	/**
	 Branch if negative flag is clear
	*/
	func BPL() -> Int {
		if(!getPBit(7)) {
			setPC(getPC() + UInt16(fetchPC()));
			return 3;
		}
		
		return 2;
	}
	
	/**
	 Branch if oVerflow flag is Clear
	*/
	func BVC() -> Int {
		if(!getPBit(6)) {
			setPC(getPC() + UInt16(fetchPC()));
			return 3;
		}
		
		return 2;
	}
	
	/**
	 Branch if oVerflow flag is Set
	*/
	func BVS() -> Int {
		if(getPBit(6)) {
			setPC(getPC() + UInt16(fetchPC()));
			return 3;
		}
		
		return 2;
	}
	
	/**
	 Clear Carry flag
	*/
	func CLC() -> Int {
		setPBit(0, value: false);
		
		return 2;
	}
	
	/**
	 Clear Decimal flag
	*/
	func CDC() -> Int {
		setPBit(3, value: false);
		
		return 2;
	}
	
	/**
	 Clear Interrupt flag
	*/
	func CLI() -> Int {
		setPBit(2, value: false);
		
		return 2;
	}
	
	/**
	 Clear oVerflow flag
	*/
	func CLV() -> Int {
		setPBit(6, value: false);
		
		return 2;
	}
    
    /**
     No OPeration
    */
    func NOP() -> Int {
        return 2;
    }
}