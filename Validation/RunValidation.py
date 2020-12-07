# -*- coding: utf-8 -*-
"""
Created on Thu Nov  5 07:40:28 2020

@author: djamal
"""

import numpy as np
import matplotlib.pyplot as plt
import math 
import pandas as pd
import sys
sys.path.append('C:/Users/DJAMAL/Documents/GitHub/Jamal_NREL2020')
sys.path.append('C:/Users/DJAMAL/Documents/GitHub/Jamal_NREL2020/Example')

#External Module
import MainBearing_Analytical_Model
import rwtparameters
import pyFrame3DDValidation as Frame3DD
from datetime import datetime


n=2000  #subset of data 

##_____________________________________________________Input Parameters____________________________________________________________________##


# Define turbine and drivetrain characteristics
Parameters = rwtparameters.RWTParameters()
FF_timestep, g, m_gr, m_s, m_rh, rho, L_gr, L_g, L_s, L_r, L_h, C1, e1, X1, Y1, C2, e2, X2 = Parameters.RWT_5MW()


#Assign Model Parameters for Analytical Model
MainBearingCalc = MainBearing_Analytical_Model.MainBearing_Analytical_Model(
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
    )


#Define load channel inputs
file = "/Users/DJAMAL/Documents/GitHub/Jamal_NREL2020/Example/5MWFastData.outb"
data, ChanName, info =  MainBearingCalc.load_binary_output(file)
rot_speed = data[:n,7] #translate rotor speed to planet speed (rpm)
torque = data[:n,5] * 1E3 # in N-m
RotThrust = data[:n,6] * 1E3 # in N
m_y = data[:n,8] * 1E3 # in N-m
m_z = data[:n,9] * 1E3 # in N-m
f_y = data[:n,10] * 1E3 # in N
f_z = data[:n,11] * 1E3 # in-N

startTime = datetime.now()

##_____________________________________________________Run Validation Model____________________________________________________________________##


# Shaft Specification for Frame3DD
diameter  = 0.75 # m
thickness = 0.25 # m
length    = 3 # m
tilt      = 5 # deg

# Hub forces & moments
i=0
f_r1v = []
f_r2v = []
f_a1v = []
f_total1v = []

while i<n:
        F_hub = [-RotThrust[i] + m_rh*g*np.sin(rho) + m_gr*g*np.sin(rho) + m_s*g*np.sin(rho),-f_y[i], -f_z[i]] 
        M_hub = [torque[i], m_y[i], m_z[i]]
        
        # Run Frame3DD and print results to screen
        F_mb1, F_mb2 = Frame3DD.run(diameter, thickness, length, tilt, F_hub, M_hub)
        f_r1v.append((F_mb1[1]**2 + F_mb1[2]**2)**0.5)
        f_r2v.append(X2*(F_mb2[1]**2 + F_mb2[2]**2)**0.5)
        f_a1v.append(F_mb1[0])
        f_total1v.append(X1*((F_mb1[1]**2 + F_mb1[2]**2)**0.5) + Y1*F_mb1[0])
        i=i+1

##_____________________________________________________Run Analytical Model____________________________________________________________________##


f_r1, f_r2, f_a1, f_total1 = MainBearingCalc.MB_forces(rho,torque, RotThrust, m_y, m_z, f_y, f_z, rot_speed, X1, Y1, X2)




##_____________________________________________________PLOTS____________________________________________________________________##

#Adjust plot settings as needed

#Radial Forces on MB1 (FWMB)
plt.subplot(211)
plt.plot(range(len(f_r1)), f_r1, alpha=0.5, label = "Analytical Model") 
plt.plot(range(len(f_r1v)), f_r1v, alpha=0.5, label = "Frame3DD") 
plt.xlabel("Time(s)")
plt.ylabel("Load (N)")
#plt.legend(loc='lower right')
plt.title("Radial Force of MB1", fontsize=9)
#plt.show()

#Axial Forces on MB1 (FWMB)
plt.subplot(212)
plt.plot(range(len(f_a1)), f_a1, alpha=0.5, label = "Analytical Model") 
plt.plot(range(len(f_a1v)), f_a1v, alpha=0.5, label = "Frame3DD") 
plt.xlabel("Time(s)")
plt.ylabel("Load (N)")
plt.legend(bbox_to_anchor=(0, 1.25), loc='lower left')
plt.title("Axial Force of MB1",fontsize=9 )
#plt.show()

plt.tight_layout()
plt.show()

# #Total Forces on MB1 (FWMB)
# plt.subplot(223)
# plt.plot(range(len(f_total1)), f_total1, alpha=0.5, label = "Analytical Model") 
# plt.plot(range(len(f_total1v)), f_total1v, alpha=0.5, label = "Frame3DD") 
# plt.xlabel("Time(s)")
# plt.ylabel("Load (N)")
# #plt.legend(loc='lower right')
# plt.title("Total Force of MB1",fontsize=9)
# #plt.show()


# #Radial Forces on MB2 (FWMB)
# plt.subplot(224)
# plt.plot(range(len(f_r2)), f_r2, alpha=0.5, label = "Analytical Model") 
# plt.plot(range(len(f_r2v)), f_r2v, alpha=0.5, label = "Frame3DD") 
# plt.xlabel("Time(s)")
# plt.ylabel("Load (N)")
# plt.legend(bbox_to_anchor=(1, 0), loc='lower left', fontsize='xx-small')
# plt.title("Radial Force of MB2", fontsize=9)
# plt.tight_layout()
# plt.show()



##_____________________________________________________L10 Calculations____________________________________________________________________##


L101v, L10_total_MB1v = MainBearingCalc.L10_Calc(rot_speed, f_total1v, C1, e1)
L102v, L10_total_MB2v = MainBearingCalc.L10_Calc(rot_speed, f_r2v, C2, e2)

print('Validation: ', datetime.now() - startTime)


print('Validation MB1 L10 Calculated: ', L10_total_MB1v, "hours or", L10_total_MB1v/24/365 , "years" )
print('Validation MB2 L10 Calculated: ', L10_total_MB2v, "hours or", L10_total_MB2v/24/365 , "years" )

L101, L10_total_MB1 = MainBearingCalc.L10_Calc(rot_speed, f_total1, C1, e1)
L102, L10_total_MB2 = MainBearingCalc.L10_Calc(rot_speed, f_r2, C2, e2)
print('MB1 L10 Calculated: ', L10_total_MB1, "hours or", L10_total_MB1/24/365 , "years" )
print('MB2 L10 Calculated: ', L10_total_MB2, "hours or", L10_total_MB2/24/365 , "years" )

print('MB1 Error: ', abs(L10_total_MB1 - L10_total_MB1v)/L10_total_MB1v)
print('MB2 Error: ', abs(L10_total_MB2 - L10_total_MB2v)/L10_total_MB2v)

##_____________________________________________________Normalized RMS Error____________________________________________________________________##

f1varray = np.array(f_total1v)
f1rarray = np.array(f_r2v)

from sklearn.metrics import mean_squared_error

NRMSE_MB1 = math.sqrt(mean_squared_error(f1varray, f_total1))/(np.amax(f1varray)-np.amin(f1varray))
NRMSE_MB2 = math.sqrt(mean_squared_error(f_r2v, f_r2))/(np.amax(f_r2v)-np.amin(f_r2v))
print('NRMSE of MB1 = ', NRMSE_MB1)
print('NRMSE of MB2 = ', NRMSE_MB2)



##_____________________________________________________BOXPLOT____________________________________________________________________##


frame1 = pd.DataFrame(f_total1, columns = ["Force (N)"])
frame1.insert(1, "Main Bearing", "MB1")
frame1.insert(2, "Model", "Analytical Model")

frame2 = pd.DataFrame(f1varray, columns = ["Force (N)"])
frame2.insert(1, "Main Bearing", "MB1")
frame2.insert(2, "Model", "Validation Model")

frame3 = pd.DataFrame(f_r2, columns = ["Force (N)"])
frame3.insert(1, "Main Bearing", "MB2")
frame3.insert(2, "Model", "Analytical Model")

frame4 = pd.DataFrame(f1rarray, columns = ["Force (N)"])
frame4.insert(1, "Main Bearing", "MB2")
frame4.insert(2, "Model", "Validation Model")

df = pd.concat([frame1,frame2,frame3,frame4])

import seaborn as sns
ax = sns.boxplot(x="Main Bearing", y="Force (N)", hue = "Model", data= df)
