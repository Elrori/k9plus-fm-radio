#!/usr/bin/env python3
"""Known-tone RF/CNR sweep, comparing actual receiver DSP transfer functions.

CNR = carrier power / total input Gaussian noise power within 5 MHz analog BPF.
Output SINAD is sine-fit (1/5/10/15 kHz) in the 48-kHz channel. This is not
an RTL-bit-exact simulation or a real-reception SNR measurement.
"""
import json
import numpy as np
from scipy import signal
from bench_1bit_real import FS,IF,AUDIO,audio_1bit_iq,pcm

def synth(fc, duration, cnr, mod, dev, seed=10):
    n=round(duration*FS)
    t=np.arange(n,dtype=np.float64)/FS
    phase=2*np.pi*fc*t - dev/mod*np.cos(2*np.pi*mod*t)
    carrier=np.cos(phase).astype(np.float32)
    noise=np.random.default_rng(seed).standard_normal(n,dtype=np.float32)
    f0=(fc-2_500_000)/(FS/2)
    f1=(fc+2_500_000)/(FS/2)
    sos=signal.butter(4,[f0,f1],btype='bandpass',output='sos')
    noise=signal.sosfilt(sos,noise).astype(np.float32)
    noise *= 10**(-cnr/20)*np.sqrt(.5)/np.std(noise)
    return (carrier+noise>0).astype(np.uint8)

def sinad(x,mod):
    t=np.arange(len(x))/AUDIO
    keep=(t>=.015)&(t<t[-1]-.005)
    a=x[keep]
    tm=t[keep]
    m=np.column_stack((np.sin(2*np.pi*mod*tm),np.cos(2*np.pi*mod*tm),np.ones(len(tm))))
    coef=np.linalg.lstsq(m,a,rcond=None)[0]
    fitted=m@coef
    sig=fitted-coef[2]
    err=a-fitted
    return round(float(10*np.log10(np.mean(sig**2)/np.mean(err**2))),3)

def main():
    rows=[]
    cases=[
      (1000,0,75000),(1000,6,75000),
      (5000,6,75000),(10000,6,75000),
      (15000,6,75000),
      (10000,12,75000),(15000,12,75000)]
    for mod,cnr,dev in cases:
        bits=synth(95e6,.08,cnr,mod,dev)
        iq=audio_1bit_iq(bits,95e6)
        results={}
        for name,cut,lag,kind in [
            ('rtl_ref',85000,1,'cic'),('lag2',85000,2,'cic'),
            ('lag4',85000,4,'cic'),('narrow70',70000,1,'cic'),
            ('fir_corr',85000,1,'fir'),
            ('fir_corr18',85000,1,'fir18'),
            ('lag2_fir18',85000,2,'fir18')]:
            audio,_=pcm(iq,cut,lag,kind)
            results[name]=sinad(audio,mod)
        row=dict(mod_hz=mod,cnr_db=cnr,freq_dev_hz=dev,**results)
        rows.append(row)
        print('SYNTH_MEASURE',json.dumps(row),flush=True)
    print('SYNTH_FINAL_JSON',json.dumps(rows),flush=True)

if __name__=='__main__':main()
