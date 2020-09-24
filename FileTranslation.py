# -*- coding: utf-8 -*-
"""
Created on Wed Sep 23 19:17:17 2020

@author: djamal
"""
import numpy as np
import struct
import os
import pandas as pd

def fread( fid, n, type):
        fmt, nbytes = {'uint8': ('B', 1), 'int16':('h', 2), 'int32':('i', 4), 'float32':('f', 4), 'float64':('d', 8)}[type]
    
        return struct.unpack(fmt * n, fid.read(nbytes * n))

def load_binary_output(filename):
        
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
            FileID = fread(fid, 1, 'int16')                        # FAST output file format, INT(2)
    
            NumOutChans = fread(fid, 1, 'int32')[0]                # The number of output channels, INT(4)
            NT = fread(fid, 1, 'int32')[0]                         # The number of time steps, INT(4)
    
            if FileID == FileFmtID_WithTime:
                TimeScl = fread(fid, 1, 'float64')                 # The time slopes for scaling, REAL(8)
                TimeOff = fread(fid, 1, 'float64')                 # The time offsets for scaling, REAL(8)
            else:
                TimeOut1 = fread(fid, 1, 'float64')                # The first time in the time series, REAL(8)
                TimeIncr = fread(fid, 1, 'float64')                # The time increment, REAL(8)
    
            ColScl = fread(fid, NumOutChans, 'float32')            # The channel slopes for scaling, REAL(4)
            ColOff = fread(fid, NumOutChans, 'float32')            # The channel offsets for scaling, REAL(4)
    
            LenDesc = fread(fid, 1, 'int32')[0]                    # The number of characters in the description string, INT(4)
            DescStrASCII = fread(fid, LenDesc, 'uint8')            # DescStr converted to ASCII
            DescStr = "".join(map(chr, DescStrASCII)).strip()
    
            ChanName = []  # initialize the ChanName cell array
            for iChan in range(NumOutChans + 1):
                ChanNameASCII = fread(fid, LenName, 'uint8')       # ChanName converted to numeric ASCII
                ChanName.append("".join(map(chr, ChanNameASCII)).strip())
    
            ChanUnit = []  # initialize the ChanUnit cell array
            for iChan in range(NumOutChans + 1):
                ChanUnitASCII = fread(fid, LenUnit, 'uint8')       # ChanUnit converted to numeric ASCII
                ChanUnit.append("".join(map(chr, ChanUnitASCII)).strip()[1:-1])
    
    
            # Get the channel time series    
            nPts = NT * NumOutChans                                     # number of data points in the file
    
            if FileID == FileFmtID_WithTime:
                PackedTime = fread(fid, NT, 'int32')                    # read the time data
                cnt = len(PackedTime)
                if cnt < NT:
                    raise Exception('Could not read entire %s file: read %d of %d time values' % (filename, cnt, NT))
            PackedData = fread(fid, nPts, 'int16')                      # read the channel data
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
    
def concatenate_seeds(inflow, case, seeds, turbine, outfile):
        
    #C:\Users\DJAMAL\Documents\Python Scripts
        '''Concatenate seeds data from FAST.Farm into a single dataframe.'''
                
        if outfile == "BINARY":
            data = []
            for seed in seeds:
                file = '/Users/DJAMAL/Documents/Python Scipts/FFarm_mod.T1.outb'.format(inflow, case, seed, turbine) 
                temp_data, channel = load_binary_output(file)
                print(str(seed) + 'temp_data size:' + print(temp_data.size))
                data.append(temp_data)
            concatenated_data = np.concatenate(data)
            frame = pd.DataFrame(concatenated_data, columns = channel)
    
    
        elif outfile == "ASCII":
            result_files = ['/Users/DJAMAL/Documents/Python Scipts/FFarm_mod.T1.outb'.format(inflow, case, seed, turbine) for seed in seeds]
            df_list = [pd.read_csv(file, delim_whitespace=True, header = [0,1], skiprows=6, error_bad_lines=False) for file in result_files]
            frame = pd.concat(df_list, axis=0, ignore_index = True)
    
        return channel, frame
    
data, Channame, info = load_binary_output("FFarm_mod.T1.outb")
print(data)
print(Channame)
print(info)