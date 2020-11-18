# -*- coding: utf-8 -*-
"""
Spyder Editor

This is a temporary script file.
"""

import filetranslation

Data = filetranslation.Filetranslation()
data, ChanName, info = Data.load_binary_output("FFarm_mod.T2.outb")
rot_speed = data[:3000,9] #translate rotor speed to planet speed (rpm)
torque = data[:3000,5] * 1E3 # in N-m
RotThrust = data[:3000,6] * 1E3 # in N
m_y = data[:3000,8] * 1E3 # in N-m
m_z = data[:3000,9] * 1E3 # in N-m
f_y = data[:3000,10] * 1E3 # in N