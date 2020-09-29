# -*- coding: utf-8 -*-
"""
Created on Wed Sep 23 19:17:17 2020

@author: djamal
"""
import numpy as np
import struct
import os
#import pandas as pd


class Filetranslation():

    def fread(self, fid, n, type):
        fmt, nbytes = {'uint8': ('B', 1), 'int16':('h', 2), 'int32':('i', 4), 'float32':('f', 4), 'float64':('d', 8)}[type]
    
        return struct.unpack(fmt * n, fid.read(nbytes * n))

    def load_binary_output(self, filename):
        
        '''Ported from ReadFASTbinary.m by Mads M Pedersen, DTU Wind
        Info about ReadFASTbinary.m:
        % Author: Bonnie Jonkman, National Renewable Energy Laboratory
        % (c) 2012, National Renewable Energy Laboratory
        %
        %  Edited for FAST v7.02.00b-bjj  22-Oct-2012
        '''
        
    
        FileFmtID_WithTime = 1                                          # File identifiers used in FAST
        LenName = 10                                                    # number of characters per channel name
        LenUnit = 10                                                    # number of characters per unit name
    
        with open(filename, 'rb') as fid:
            FileID = self.fread(fid, 1, 'int16')                        # FAST output file format, INT(2)
    
            NumOutChans = self.fread(fid, 1, 'int32')[0]                # The number of output channels, INT(4)
            NT = self.fread(fid, 1, 'int32')[0]                         # The number of time steps, INT(4)
    
            if FileID == FileFmtID_WithTime:
                TimeScl = self.fread(fid, 1, 'float64')                 # The time slopes for scaling, REAL(8)
                TimeOff = self.fread(fid, 1, 'float64')                 # The time offsets for scaling, REAL(8)
            else:
                TimeOut1 = self.fread(fid, 1, 'float64')                # The first time in the time series, REAL(8)
                TimeIncr = self.fread(fid, 1, 'float64')                # The time increment, REAL(8)
    
            ColScl = self.fread(fid, NumOutChans, 'float32')            # The channel slopes for scaling, REAL(4)
            ColOff = self.fread(fid, NumOutChans, 'float32')            # The channel offsets for scaling, REAL(4)
    
            LenDesc = self.fread(fid, 1, 'int32')[0]                    # The number of characters in the description string, INT(4)
            DescStrASCII = self.fread(fid, LenDesc, 'uint8')            # DescStr converted to ASCII
            DescStr = "".join(map(chr, DescStrASCII)).strip()
    
            ChanName = []  # initialize the ChanName cell array
            for iChan in range(NumOutChans + 1):
                ChanNameASCII = self.fread(fid, LenName, 'uint8')       # ChanName converted to numeric ASCII
                ChanName.append("".join(map(chr, ChanNameASCII)).strip())
    
            ChanUnit = []  # initialize the ChanUnit cell array
            for iChan in range(NumOutChans + 1):
                ChanUnitASCII = self.fread(fid, LenUnit, 'uint8')       # ChanUnit converted to numeric ASCII
                ChanUnit.append("".join(map(chr, ChanUnitASCII)).strip()[1:-1])
    
    
            # Get the channel time series    
            nPts = NT * NumOutChans                                     # number of data points in the file
    
            if FileID == FileFmtID_WithTime:
                PackedTime = self.fread(fid, NT, 'int32')                    # read the time data
                cnt = len(PackedTime)
                if cnt < NT:
                    raise Exception('Could not read entire %s file: read %d of %d time values' % (filename, cnt, NT))
            PackedData = self.fread(fid, nPts, 'int16')                      # read the channel data
            cnt = len(PackedData)
            if cnt < nPts:
                raise Exception('Could not read entire %s file: read %d of %d values' % (filename, cnt, nPts))
    
        # Scale the packed binary to real data    
        data = np.array(PackedData).reshape(NT, NumOutChans)
        data = (data - ColOff) / ColScl
    
        if FileID == FileFmtID_WithTime:
            time = (np.array(PackedTime) - TimeOff) / TimeScl;
        else:
            time = TimeOut1 + TimeIncr * np.arange(NT)
    
        data = np.concatenate([time.reshape(NT, 1), data], 1)
    
        info = {'name': os.path.splitext(os.path.basename(filename))[0],
                'description': DescStr,
                'attribute_names': ChanName,
                'attribute_units': ChanUnit}
    
        return data, ChanName, info
    
  
    
