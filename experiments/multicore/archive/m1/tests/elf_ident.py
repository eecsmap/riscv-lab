#!/usr/bin/env python3
"""Load-semantic identity of a RISC-V ELF64: what the loader actually uses.

A whole-file SHA differs between two builds of the same program when only metadata differs (gcc's
temporary object names, for one), and `objcopy -O binary` equality alone cannot exclude a different
entry point, load address or symbol (codex-mc-m1-verification-closeout, item 3). So this digests exactly:
the entry point; every PT_LOAD segment's vaddr, paddr, filesz, memsz, flags, its file bytes and its
zero-fill size; and the addresses of the symbols the host loader and HTIF use (tohost, fromhost,
_start, plus any symbol the program exports that starts with `htif_`).

Pure Python, no toolchain dependency, so the checker's self-test can corrupt bytes and see it change.

  elf_ident.py <file.elf> [...]      prints "<digest>  <file>" per file, like sha256sum
"""
import hashlib, struct, sys


def ident(path):
    b = open(path, 'rb').read()
    if b[:4] != b'\x7fELF' or b[4] != 2 or b[5] != 1: raise ValueError(f'{path}: not a little-endian ELF64')
    (e_type, e_machine, e_version, e_entry, e_phoff, e_shoff, e_flags, e_ehsize, e_phentsize, e_phnum,
     e_shentsize, e_shnum, e_shstrndx) = struct.unpack_from('<HHIQQQIHHHHHH', b, 16)
    h = hashlib.sha256()
    h.update(f'entry={e_entry:#x}\n'.encode())
    for i in range(e_phnum):
        (p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align) = struct.unpack_from('<IIQQQQQQ', b, e_phoff + i * e_phentsize)
        if p_type != 1: continue   # PT_LOAD only
        seg = b[p_offset:p_offset + p_filesz]
        h.update(f'load vaddr={p_vaddr:#x} paddr={p_paddr:#x} filesz={p_filesz} memsz={p_memsz} flags={p_flags} zerofill={p_memsz - p_filesz}\n'.encode())
        h.update(hashlib.sha256(seg).digest())
    # symbols: find .symtab and its .strtab
    secs = []
    for i in range(e_shnum):
        (sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size, sh_link, sh_info, sh_addralign, sh_entsize) = struct.unpack_from('<IIQQQQIIQQ', b, e_shoff + i * e_shentsize)
        secs.append((sh_type, sh_offset, sh_size, sh_link, sh_entsize))
    syms = {}
    for (t, off, size, link, ent) in secs:
        if t != 2: continue   # SHT_SYMTAB
        (_, stroff, strsize, _, _) = secs[link]
        strtab = b[stroff:stroff + strsize]
        for j in range(size // ent):
            (st_name, st_info, st_other, st_shndx, st_value, st_size) = struct.unpack_from('<IBBHQQ', b, off + j * ent)
            end = strtab.find(b'\0', st_name); name = strtab[st_name:end].decode(errors='replace')
            if name in ('tohost', 'fromhost', '_start') or name.startswith('htif_'):
                syms[name] = st_value
    for k in sorted(syms): h.update(f'sym {k}={syms[k]:#x}\n'.encode())
    return h.hexdigest(), e_entry, syms


def main():
    for p in sys.argv[1:]:
        d, entry, syms = ident(p)
        print(f'{d}  {p.split("/")[-1]}')


if __name__ == '__main__':
    main()
