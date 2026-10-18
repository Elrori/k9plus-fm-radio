#!/usr/bin/env python3
"""Offline float-DSP K9RAW1 A/B on unchanged ADC bits; metrics are not true SNR."""
import hashlib
import json
import struct
from pathlib import Path
import numpy as np
from scipy import signal

FS=240_000_000
IF=960_000
AUDIO=48_000
RAW=Path('captures/raw_2026-10-18/fm_band_snapshot.k9raw')

def cic(r):
    p=np.ones(r,dtype=np.float32)/r
    return np.convolve(np.convolve(p,p),p).astype(np.float32)

def fir(cut):
    n=np.arange(101)-50
    h=2*cut/IF*np.sinc(2*cut/IF*n)*np.kaiser(101,7.5)
    h/=np.sum(h)
    q=np.rint(h*2**18).astype(np.int64)
    q[50]+=2**18-q.sum()
    return q/2**18

def audio_1bit_iq(bits,fc):
    n=np.arange(len(bits),dtype=np.float64)
    n*=2*np.pi*fc/FS
    s=bits.astype(np.float32)*2-1
    c=np.cos(n).astype(np.float32)
    c*=s
    i=signal.upfirdn(cic(250),c,down=250)
    del c
    np.sin(n,out=n)
    q=signal.upfirdn(cic(250),-n.astype(np.float32)*s,down=250)
    m=min(len(i),len(q))
    return i[:m]+1j*q[:m]

def pcm(iq,cut,lag):
    x=signal.lfilter(fir(cut),[1.],iq)
    p=x[lag:]*np.conj(x[:-lag])
    pp=signal.upfirdn(cic(20),p,down=20)
    d=np.angle(pp)/lag
    dc=signal.lfilter([1/128.],[1,-127/128],d)
    return signal.lfilter([0.328125],[1,-0.671875],d-dc),np.abs(pp)

def stats(audio,p):
    a=audio[800:-250]  # avoid both ends; first 16.7 ms discarded
    rms=np.std(a)
    hi=signal.sosfilt(signal.butter(4,8000,fs=AUDIO,btype='highpass',output='sos'),a)
    return dict(rms=float(rms),hf8k_rms=float(np.std(hi)),
                outlier_fraction=float(np.mean(np.abs(a-np.median(a))>4*rms)),
                corr_median=float(np.median(p)))

def main():
    b=RAW.read_bytes()
    h=struct.Struct('<8sIIIIIIQQIIII')
    f=h.unpack_from(b)
    assert f[0]==b'K9RAW1\0\0' and f[1]==64 and f[2]==FS
    assert (len(b)-64)*8==f[8] and f[10]==0 and f[11]==0
    sha=hashlib.sha256(b).hexdigest().upper()
    expected=json.loads(Path(str(RAW)+'.json').read_text())['sha256']
    assert sha==expected
    bits=np.unpackbits(np.frombuffer(b,dtype=np.uint8,offset=64),bitorder='little')
    assert len(bits)==f[8]
    print('CAPTURE_VERIFIED',sha,'samples',len(bits),'ones',float(np.mean(bits)),flush=True)
    result={}
    for fc in [94_700_000,95_000_000,96_000_000,96_800_000]:
        iq=audio_1bit_iq(bits,fc)
        result[str(fc)]={}
        for name,cut,lag in [('rtl_ref',85000,1),('narrow70',70000,1),
                              ('lag2',85000,2),('lag4',85000,4),
                              ('narrow70_lag4',70000,4)]:
            sound,amp=pcm(iq,cut,lag)
            result[str(fc)][name]=stats(sound,amp)
            print('MEASURE',fc,name, json.dumps(result[str(fc)][name]),flush=True)
    print('FINAL_JSON',json.dumps(result),flush=True)

if __name__=='__main__':main()
