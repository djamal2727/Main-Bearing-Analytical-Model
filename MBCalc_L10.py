# -*- coding: utf-8 -*-
"""
Created on Mon Sep 28 20:41:43 2020

@author: djamal
"""
import numpy as np
import matplotlib.pyplot as plt
import math
import pandas as pd

#External Module
import filetranslation
import MB_Model


# Define turbine and drivetrain characteristics
FF_timestep = 0.025  
g = 9.81                        #gravitational acceleration, m*s^-2
m_gr = (144.963+226.629)*1000   #mass of generator, kg
m_s = 15.734*1000               #mass of shaft, kg
m_rh = 385*1000                 #mass of rotor+hub, kg 
rho = 6*math.pi/180             #tilt angle, radians

L_gr = 0.9                      #distance from generator COM to MB1, m
L_g = 1.2                       #distance from MB1 to MB2, m
L_s = 0.25                      #distance from shaft COM to MB1, m
L_r = 3.638                     #distance from hub/rotor COM to MB1
#f_xr = 10000                   #Need LSSShftFys or LSSGagFys
L_h = 11.35                     #Hub overhang, m
C = 934000*4.15*4.44822         #Capacity of Timken Bearing (Converted and Scaled), N
e = 10/3                        #constant for roller bearings
X = 1.2                         #rotation factor
Y = 0.39                        #Estimated thrust factor

#Define load channel inputs
Data = filetranslation.Filetranslation()
data, ChanName, info = Data.load_binary_output("FFarm_mod.T1.outb")
rot_speed = data[:,16] #translate rotor speed to planet speed (rpm)
torque = data[:,17] * 1E3 # in N-m
m_y = data[:,7] * 1E3 # in N-m
m_z = data[:,8] * 1E3 # in N-m

MainBearingCalc = MB_Model.MB_Model(
    FF_timestep = FF_timestep,
    m_s = m_s,
    m_gr = m_gr,
    m_rh =  m_rh,
    g = g,
    L_gr = L_gr,
    L_g = L_g,
    L_s = L_s,
    L_r = L_r,
    L_h = L_h,
    rho = rho,
    C = C,
    e = e,
    X = X,
    Y = Y
    )

f_r1, f_r2, f_a1, f_total1 = MainBearingCalc.MB_forces(rho,torque,m_y,m_z, rot_speed)
MainBearingCalc.plot_loads(f_r1, f_a1, f_total1, f_r2, "Radial Force on MB1", "Axial Force on MB1", "Resultant Force on MB1","Radial Force on MB2", "Time (s)", "Load (N-m)" )

L101, L10_total_MB1 = MainBearingCalc.L10_Calc(rot_speed, f_total1)
L102, L10_total_MB2 = MainBearingCalc.L10_Calc(rot_speed, f_r2)
print('MB1 L10 Calculated: ', L10_total_MB1, "hours or", L10_total_MB1/24/365 , "years" )
print('MB2 L10 Calculated: ', L10_total_MB2, "hours or", L10_total_MB2/24/365 , "years" )
