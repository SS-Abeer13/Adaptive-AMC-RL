#!/usr/bin/env python3
"""Forwarder to Optimized/v17/release/reproduce_tables.py"""
import os, sys, subprocess

TARGET = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Optimized", "v17", "release", "reproduce_tables.py")
if not os.path.exists(TARGET):
    TARGET = os.path.join(os.path.dirname(os.path.abspath(__file__)), "reproduce_tables.py")

sys.exit(subprocess.call([sys.executable, TARGET] + sys.argv[1:]))
