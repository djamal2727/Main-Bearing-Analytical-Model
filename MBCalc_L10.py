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
import rwtparameters


# Define turbine and drivetrain characteristics
Parameters = rwtparameters.RWTParameters()
FF_timestep, g, m_gr, m_s, m_rh, rho, L_gr, L_g, L_s, L_r, L_h, L_b, C, e, X, Y = Parameters.RWT_15MW()
#FF_timestep, g, m_gr, m_s, m_rh, rho, L_gr, L_g, L_s, L_r, L_h, L_b, C, e, X, Y = Parameters.RWT_10MW()

#Define load channel inputs
Data = filetranslation.Filetranslation()
data, ChanName, info = Data.load_binary_output("FFarm_mod.T1.outb")
rot_speed = data[:,16] #translate rotor speed to planet speed (rpm)
torque = data[:,17] * 1E3 # in N-m
RotThrust = data[:,18] * 1E3 # in N
m_y = data[:,7] * 1E3 # in N-m
m_z = data[:,8] * 1E3 # in N-m
# Ftipy =
# Ftipz = 
# Fbz =
# Fby =


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

f_r1, f_r2, f_a1, f_total1 = MainBearingCalc.MB_forces(rho,torque, RotThrust, m_y,m_z, rot_speed)
MainBearingCalc.plot_loads(f_r1, f_a1, f_total1, f_r2, "Radial Force on MB1", "Axial Force on MB1", "Resultant Force on MB1","Radial Force on MB2", "Time (s)", "Load (N-m)" )


L101, L10_total_MB1 = MainBearingCalc.L10_Calc(rot_speed, f_total1)
L102, L10_total_MB2 = MainBearingCalc.L10_Calc(rot_speed, f_r2)
print('MB1 L10 Calculated: ', L10_total_MB1, "hours or", L10_total_MB1/24/365 , "years" )
print('MB2 L10 Calculated: ', L10_total_MB2, "hours or", L10_total_MB2/24/365 , "years" )

#MB1_total, MB1_r, MB1_a, MB2_total = MainBearingCalc.MB_forces2(rho,torque, RotThrust, m_y, m_z, rot_speed, Ftipz, Ftipy, Fbz, Fby)
#MainBearingCalc.plot_loads(MB1_r, MB1_a,MB1_total, MB2_total, "Radial Force on MB1", "Axial Force on MB1", "Resultant Force on MB1","Radial Force on MB2", "Time (s)", "Load (N-m)" )
#L101, L10_total_MB1 = MainBearingCalc.L10_Calc(rot_speed, MB1_total)
#L102, L10_total_MB2 = MainBearingCalc.L10_Calc(rot_speed, MB2_total)
#print('MB1 L10 Calculated: ', L10_total_MB1, "hours or", L10_total_MB1/24/365 , "years" )
#print('MB2 L10 Calculated: ', L10_total_MB2, "hours or", L10_total_MB2/24/365 , "years" )