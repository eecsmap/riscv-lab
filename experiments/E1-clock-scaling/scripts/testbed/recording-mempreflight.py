#!/usr/bin/env python3
"""Stands in for mem-preflight.py; exits FAKE_MEM_RC."""
import os, sys
open(os.environ["E1_REC"], "a").write(f"MEMPREFLIGHT {' '.join(sys.argv[1:])}\n")
sys.exit(int(os.environ.get("FAKE_MEM_RC", "0")))
