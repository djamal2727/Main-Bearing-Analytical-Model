# -*- coding: utf-8 -*-
"""
Created on Mon Sep 28 20:01:58 2020

@author: djamal
"""

import numpy as np
import matplotlib.pyplot as plt
import math
import struct
import os


class MainBearing_Analytical_Model():
    
    def __init__(self, FF_timestep, m_s, m_gr, m_rh, g, L_gr, L_g, L_s, L_r, L_h, rho):
        
        '''Instantiate LayoutOptimization object and parameter values.'''

        self.FF_timestep = FF_timestep      # FAST.Farm timestep for outputs
        self.m_s = m_s                      # shaft mass
        self.m_gr = m_gr                    # generator mass
        self.m_rh = m_rh                    # rotor-hub mass
        self.g = g                          # gravitational force
        self.L_gr = L_gr                    # distance from generator COM to MB1, m
        self.L_g = L_g                      # distance from MB1 to MB2, m
        self.L_s = L_s                      # distance from shaft COM to MB1, m
        self.L_r = L_r                      # distance from hub/rotor COM to MB1
        self.L_h = L_h                      # hub overhang, m
        self.rho = rho                      # bedplate tilting angle (if don't want to include, set to 0 degrees)
        
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
    

        

    def MB_forces(self, rho, torque, RotThrust, m_y, m_z, f_y, f_z, rot_speed, X1, Y1, X2):
        
        #Equations adapted from DNV Guidelines and Smith, NTNU Master Thesis 2012
        
        m1 = m_y - self.m_rh*self.g*np.cos(self.rho)*self.L_r - self.m_gr*self.g*np.cos(self.rho)*self.L_gr + self.m_s*self.g*self.L_s*np.cos(self.rho)
        m2 = (f_y)*self.L_r + (m_z)
        f_r2 = X2*((1/self.L_g)*(m1**2 + m2**2)**0.5)
        
        
        f_r1 = (1/X2)*f_r2 + ((f_y)**2 + (-f_z)**2)**0.5
        f_a1 = -RotThrust + self.m_rh*self.g*np.sin(self.rho) + self.m_gr*self.g*np.sin(self.rho) + self.m_s*self.g*np.sin(self.rho)
        f_total1 = X1*f_r1 + Y1*f_a1
        
        return f_r1,f_r2, f_a1,f_total1
    


    def L10_Calc(self, rot_speed, MB_forces, C, e):
        T = self.FF_timestep / (len(rot_speed) * self.FF_timestep - self.FF_timestep) # fraction of total running time at a given load and speed
        L10 = [T/((10**6/(60*i))*(C/abs(j))**e) for i,j in zip(abs(rot_speed), MB_forces)]
        # 10**6 million race revolutions conversion factor
        # 60 min/hr conversion factor
        # i: planet speed 
        # C: bearing basic dynamic load rating or capacity, N (the load that a bearing can carry for 1 million inner-race revolutions with a 90% probability of survival)
        # e: load-life exponent (determined by Lundberg and Palmgren to be 3 for ball bearings and 10/3 for cylindrical roller bearings)
        L10_total = 1/sum(L10) 
        return L10, L10_total
    
    
    def plot_loads(self, x1, x2, x3, x4, x1_label, x2_label, x3_label, x4_label, xlabel, ylabel):
        
        '''Plot Main Bearing loads'''
        
        #MB1 PLOT
        plt.plot(range(len(x1)), x1, alpha=0.5, label = "Radial Force on MB1") 
        plt.plot(range(len(x3)), x2, alpha=0.5, label = "Axial Force on MB1") 
        plt.plot(range(len(x4)), x3, alpha=0.5, label = "Resultant Force on MB1")
        plt.tight_layout()
        plt.xlabel(xlabel)
        plt.ylabel(ylabel)
        plt.legend(loc='lower right')
        plt.show()
        
        
        #MB2 PLOT
        plt.plot(range(len(x2)), x4, alpha=0.5, label = "Radial Force on MB2")  
        plt.tight_layout()
        plt.xlabel(xlabel)
        plt.ylabel(ylabel)
        plt.legend(loc='lower right')
        plt.show()


