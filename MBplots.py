# -*- coding: utf-8 -*-
"""
Created on Mon Sep 21 19:29:18 2020
@author: djamal
"""

#Adapted from RBLO Code by C. Clark

import numpy as np
import matplotlib.pyplot as plt
#from scipy.optimize import fsolve


#Internal Modules
import pandas as pd
import math
#from datetime import datetime
#from scipy import stats


#Define load channel inputs
frame = pd.read_csv('/Users/DJAMAL/Documents/Python Scripts/Case_A_8_dist630.0_off0.0_T2.csv', delim_whitespace=False, header = [0], skiprows=[1], error_bad_lines=False)
rot_speed = frame['RotSpeed'].apply(lambda x: x).values #translate rotor speed to planet speed (rpm)
torque = frame['RotTorq'].apply(lambda x: x * 1E3).values # in N-m
m_y = frame['LSSGagMys'].apply(lambda x: x * 1E3).values # in N-m
m_z = frame['LSSGagMzs'].apply(lambda x: x * 1E3).values # in N-m

# Define turbine and drivetrain characteristics
FF_timestep = 0.025  
g = 9.81                        #gravitational acceleration, m*s^-2
m_gr = 144.963*1000             #mass of generator, kg
m_s = 15.734*1000               #mass of shaft, kg
m_rotorhub = 385*1000           #mass of rotor+hub, kg 
a = 6*math.pi/180               #tilt angle, radians

y_gr = 0.9                      #distance from generator COM to MB1, m
y_g = 1.2                       #distance from MB1 to MB2, m
y_s = 0.25                      #distance from shaft COM to MB1, m
y_r = 3.638                     #distance from hub/rotor COM to MB1
f_xr = 10000                    #Need LSSShftFys or LSSGagFys
f_z = m_rotorhub*g              #Weight of rotor + hub, N

C = 934000*4.15*4.44822         #Capacity of Timken Bearing (Converted and Scaled), N
e = 10/3                        #constant for roller bearings


def MB2_forces(a, torque, m_y, m_z):
    m1 = m_y - m_gr*g*np.cos(a)*y_gr + m_s*g*y_s*np.cos(a)
    m2 = f_xr*y_r + m_z
    f_r2 = (1/y_g)*(m1**2 + m2**2)**0.5
    return f_r2

   
def MB1_forces(a, torque, m_y, m_z):
    f_r2 = MB2_forces(a,torque,m_y,m_z)
    f_r1 = f_r2 + (f_xr**2 + f_z**2)**0.5
    f_a1 = -torque + m_rotorhub*g*np.sin(a) + m_gr*g*np.sin(a) + m_s*g*np.sin(a)
    f_total1 = (f_r1**2 + f_a1**2)**0.5
    return f_r1,f_a1,f_total1


def L10_Calc(rot_speed,MB_forces):
    T = FF_timestep / (len(rot_speed) * FF_timestep - FF_timestep) # fraction of total running time at a given load and speed
    L10 = [T/((10**6/(60*i))*(C/abs(j))**e) for i,j in zip(rot_speed, MB_forces)]
    L10_total = 1/sum(L10) 
    return L10, L10_total


f_r2 = MB2_forces(a,torque,m_y,m_z)
f_r1, f_a1, f_total1 = MB1_forces(a,torque,m_y,m_z)
L101, L10_total_MB1 = L10_Calc(rot_speed, f_total1)
L102, L10_total_MB2 = L10_Calc(rot_speed, f_r2)

x1 = f_r1
x2 = f_r2
x3 = f_a1
x4 = f_total1

#MB1 PLOT
plt.plot(range(len(x1)), x1, alpha=0.5, label = "Radial Force on MB1") 
plt.plot(range(len(x3)), x3, alpha=0.5, label = "Axial Force on MB1") 
plt.plot(range(len(x4)), x4, alpha=0.5, label = "Resultant Force on MB1")
plt.tight_layout()
plt.xlabel("Time (s)")
plt.ylabel("Load (N-m)")
plt.legend(loc='lower right')
plt.show()

#MB2 PLOT
plt.plot(range(len(x2)), x2, alpha=0.5, label = "Radial Force on MB2")  
plt.tight_layout()
plt.xlabel("Time (s)")
plt.ylabel("Load (N-m)")
plt.legend(loc='lower right')
plt.show()


print('MB1 L10 Calculated: ', L10_total_MB1, "hours or", L10_total_MB1/24/365 , "years" )
print('MB2 L10 Calculated: ', L10_total_MB2, "hours or", L10_total_MB2/24/365 , "years" )
