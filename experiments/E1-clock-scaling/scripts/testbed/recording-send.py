#!/usr/bin/env python3
"""Stands in for send-file.py. Records the upload; fails for the destination named by FAKE_SEND_FAIL."""
import os, sys
open(os.environ["E1_REC"], "a").write(f"SEND {sys.argv[1]} -> {sys.argv[2]}\n")
fail = os.environ.get("FAKE_SEND_FAIL", "")
sys.exit(1 if fail and fail in sys.argv[2] else 0)
