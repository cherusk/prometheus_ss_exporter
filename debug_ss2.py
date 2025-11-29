#!/usr/bin/env python3
"""
Debug script to test ss2 command execution
"""
import subprocess
import sys
import os

def main():
    print("=== SS2 Debug Script ===")
    print(f"Python version: {sys.version}")
    print(f"Current working directory: {os.getcwd()}")
    print(f"Environment PATH: {os.environ.get('PATH', 'Not set')}")
    
    print("\n=== Testing Python import ===")
    try:
        import pyroute2
        print(f"✅ pyroute2 version: {pyroute2.__version__}")
        print(f"✅ pyroute2 location: {pyroute2.__file__}")
        
        from pyroute2.netlink import diag
        print("✅ pyroute2.netlink.diag import successful")
        
    except Exception as e:
        print(f"❌ pyroute2 import failed: {e}")
        return 1
    
    print("\n=== Testing ss2 command ===")
    cmd = [sys.executable, "-m", "pyroute2.netlink.diag.ss2", "--tcp", "--process"]
    print(f"Running: {' '.join(cmd)}")
    
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10
        )
        
        print(f"Return code: {result.returncode}")
        print(f"STDOUT length: {len(result.stdout)} characters")
        print(f"STDERR length: {len(result.stderr)} characters")
        
        if result.stdout:
            print(f"STDOUT (first 500 chars):\n{result.stdout[:500]}")
        
        if result.stderr:
            print(f"STDERR (first 500 chars):\n{result.stderr[:500]}")
        
        if result.returncode == 0:
            print("✅ SS2 command succeeded")
            return 0
        else:
            print("❌ SS2 command failed")
            return 1
            
    except subprocess.TimeoutExpired:
        print("❌ SS2 command timed out")
        return 1
    except Exception as e:
        print(f"❌ Exception running SS2 command: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())