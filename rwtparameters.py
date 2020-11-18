# -*- coding: utf-8 -*-
"""
Created on Wed Sep 30 19:14:18 2020

@author: djamal
"""
import math

class RWTParameters():
    
    def RWT_15MW(self):
        # Define turbine and drivetrain characteristics
       FF_timestep = 0.025  
       g = 9.81                        #gravitational acceleration, m*s^-2
       m_gr = 371.592*1000             #mass of generator, kg
       m_s = 15.734*1000               #mass of shaft, kg
       m_rh = 385*1000                 #mass of rotor+hub, kg 
       rho = 6*math.pi/180             #tilt angle, radians
       
       L_gr = 0.9                      #distance from generator COM to MB1, m
       L_g = 1.2                       #distance from MB1 to MB2, m
       L_s = 0.25                      #distance from shaft COM to MB1, m
       L_r = 3.638                     #distance from hub/rotor COM to MB1
       L_h = 11.35                     #Hub overhang, m
       C = 934000*4.15*4.44822        #Capacity of Timken Bearing (Converted and Scaled), N
       e = 10/3                        #constant for roller bearings
       X = 1.2                         #rotation factor
       Y = 0.39                        #Estimated thrust factor
       return FF_timestep, g, m_gr, m_s, m_rh, rho, L_gr, L_g, L_s, L_r, L_h, C, e, X, Y
   
    def RWT_10MW(self):
        # Define turbine and drivetrain characteristics
       FF_timestep = 0.025  
       g = 9.81                        #gravitational acceleration, m*s^-2
       m_gr = 357.3 *1000              #mass of generator, kg
       m_s = 78894                     #mass of shaft, kg
       m_rh = 224807                   #mass of rotor+hub, kg 
       rho = 5*math.pi/180             #tilt angle, radians
       
       L_gr = -0.78                    #distance from generator COM to MB1, m
       L_g = 4.62                      #distance from MB1 to MB2, m
       L_s = 1.25                      #distance from shaft COM to MB1, m
       L_r = 3.618                     #distance from hub/rotor COM to MB1
       L_h = 10.039                    #Hub overhang, m
       C = 934000*4.15*4.44822         #Capacity of Timken Bearing (Converted and Scaled), N
       e = 10/3                        #constant for roller bearings
       X = 1.2                         #rotation factor
       Y = 0.39                        #Estimated thrust factor
       return FF_timestep, g, m_gr, m_s, m_rh, rho, L_gr, L_g, L_s, L_r, L_h, C, e, X, Y
   
    def RWT_5MW(self):
        # Define turbine and drivetrain characteristics
       FF_timestep = 0.025  
       g = 9.81                        #gravitational acceleration, m*s^-2
       m_gr = 131 * 1000              #mass of generator, kg
       m_s = 28.5 * 1000               #mass of shaft, kg
       m_rh = 108220                   #mass of rotor+hub, kg 
       rho = 5*math.pi/180             #tilt angle, radians
       
       L_gr = -0.85                    #distance from generator COM to MB1, m
       L_g = 2                         #distance from MB1 to MB2, m
       L_s = -0.85                      #distance from shaft COM to MB1, m
       L_r = 0.65                     #distance from hub/rotor COM to MB1
       L_h = 4                        #Hub overhang, m
           
      #Upwind Main Bearing, MB1
       C1 = 8090*1000                   #Capacity of  Bearing , N
       e1 = 10/3                        #constant for roller bearings
       X1 = 1                            #rotation factor
       Y1 = 1.15                          #Estimated thrust factor
      #Downwind Main Bearing, MB2
       C2 = 10061*1000                  #Capacity of  Bearing , N
       e2 = 10/3                        #constant for roller bearings
       X2 = 3.2                            #rotation factor
 
       return FF_timestep, g, m_gr, m_s, m_rh, rho, L_gr, L_g, L_s, L_r, L_h, C1, e1, X1, Y1, C2, e2, X2
   
    