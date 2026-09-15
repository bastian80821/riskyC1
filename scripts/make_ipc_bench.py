def addi(rd,rs1,imm): return (((imm&0xFFF)<<20)|(rs1<<15)|(0<<12)|(rd<<7)|0b0010011)&0xFFFFFFFF
def lui(rd,i20):      return ((i20&0xFFFFF)<<12|(rd<<7)|0b0110111)&0xFFFFFFFF
def rt(rd,a,b,f3,f7=0): return (f7<<25)|(b<<20)|(a<<15)|(f3<<12)|(rd<<7)|0b0110011
def add(rd,a,b): return rt(rd,a,b,0)
def sub(rd,a,b): return rt(rd,a,b,0,0x20)
def xor_(rd,a,b):return rt(rd,a,b,4)
def sltu(rd,a,b):return rt(rd,a,b,3)
def srli(rd,a,sh): return ((sh&0x1F)<<20)|(a<<15)|(0b101<<12)|(rd<<7)|0b0010011
def slli(rd,a,sh): return ((sh&0x1F)<<20)|(a<<15)|(0b001<<12)|(rd<<7)|0b0010011
def andi(rd,a,imm):return (((imm&0xFFF)<<20)|(a<<15)|(0b111<<12)|(rd<<7)|0b0010011)&0xFFFFFFFF
def st(rs2,rs1,imm,f3):
    i=imm&0xFFF
    return (((i>>5)&0x7F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((i&0x1F)<<7)|0b0100011
def ld(rd,rs1,imm,f3): return (((imm&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|0b0000011)&0xFFFFFFFF
def br(a,b,i,f3):
    x=i&0x1FFF
    return (((x>>12)&1)<<31)|(((x>>5)&0x3F)<<25)|(b<<20)|(a<<15)|(f3<<12)|(((x>>1)&0xF)<<8)|(((x>>11)&1)<<7)|0b1100011
def bne(a,b,i): return br(a,b,i,1)
def blt(a,b,i): return br(a,b,i,4)
def jal(rd,i):
    x=i&0x1FFFFF
    return (((x>>20)&1)<<31)|(((x>>1)&0x3FF)<<21)|(((x>>11)&1)<<20)|(((x>>12)&0xFF)<<12)|(rd<<7)|0b1101111
SW,LW=2,2
p=[]
def emit(w): p.append(w)
def here(): return len(p)*4

emit(lui(2,0x1))                  # x2 = UART/IO base 0x1000
emit(addi(5,0,0x200))             # x5 = data area

emit(ld(20,2,8,LW))               # cycles before
emit(ld(21,2,12,LW))              # instret before

# ---------- workload: 200 iterations, mixed ALU / load-use / branch ----------
emit(addi(10,0,200))              # n
emit(addi(11,0,0))                # i
emit(addi(12,0,0))                # acc
loop = here()
emit(add (12,12,11))              # acc += i          dependent ALU
emit(slli(13,11,2))               # tmp = i*4
emit(add (13,13,5))               # tmp = base+i*4    dependent
emit(st  (12,5,0,SW))             # store acc         memory write
emit(ld  (14,5,0,LW))             # load it back      LOAD-USE hazard
emit(xor_(12,12,14))              # acc ^= loaded     dependent on load
emit(add (12,12,11))
emit(sltu(15,11,10))
emit(addi(11,11,1))               # i++
emit(blt (11,10, loop-here()))    # taken 199 times   branch flush
# ----------------------------------------------------------------------------

emit(ld(22,2,8,LW))               # cycles after
emit(ld(23,2,12,LW))              # instret after
emit(sub(22,22,20))               # elapsed cycles
emit(sub(23,23,21))               # elapsed instructions

# ---- emit a marker then 4 raw bytes of each counter, little-endian ----
def putc(reg):
    emit(ld(4,2,4,LW)); emit(bne(4,0,-4)); emit(st(reg,2,0,SW))
def putlit(c):
    emit(addi(16,0,c)); putc(16)
def putword(reg):
    for sh in (0,8,16,24):
        emit(srli(17,reg,sh)); emit(andi(17,17,0xFF)); putc(17)

putlit(0xAA)      # marker so the host can find the start
putword(22)       # cycles
putword(23)       # instructions
putlit(0x55)      # end marker
emit(jal(0,0))

open('bench.hex','w').write("".join(f"{w:08X}\n" for w in p))
print(f"{len(p)} words")
