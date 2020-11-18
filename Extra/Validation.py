
from collections import namedtuple
import numpy as np
import pyframe3dd.pyframe3dd as frame3dd
import matplotlib.pyplot as plt
import math

import rwtparameters
import MB_Model

# Define turbine and drivetrain characteristics
Parameters = rwtparameters.RWTParameters()
#FF_timestep, g, m_gr, m_s, m_rh, rho, L_gr, L_g, L_s, L_r, L_h, C, e, X, Y = Parameters.RWT_15MW()
#FF_timestep, g, m_gr, m_s, m_rh, rho, L_gr, L_g, L_s, L_r, L_h, C, e, X, Y = Parameters.RWT_10MW()
FF_timestep, g, m_gr, m_s, m_rh, rho, L_gr, L_g, L_s, L_r, L_h, C, e, X, Y = Parameters.RWT_5MW()


gravity = 9.80633
RIGID = 1
FREE  = 0

Material = namedtuple('Material', ['E', 'G', 'rho'])
Steel = Material(200e9, 79.3e9, 7850.0)



class Tube:
    def __init__(self, D, t):
        self.D=D
        self.t=t
        
    @property
    def Area(self): #Cross sectional area of tube
        return (self.D**2-(self.D-2*self.t)**2)* np.pi/4

    @property
    def Jxx(self): #2nd area moment of inertia w.r.t. x-x axis (Jxx=Jyy for tube)
        return (self.D**4-(self.D-2*self.t)**4)* np.pi/64

    @property
    def Jyy(self): #2nd area moment of inertia w.r.t. x-x axis (Jxx=Jyy for tube)
        return self.Jxx

    @property
    def J0(self):  #polar moment of inertia w.r.t. z-z axis (torsional)
        return (2.0 * self.Jxx)

    @property
    def Asy(self): #Shear Area for tubular cross-section
        Ri=self.D/2-self.t
        Ro=self.D/2
        return self.Area / ( 1.124235 + 0.055610*(Ri/Ro) + 1.097134*(Ri/Ro)**2 - 0.630057*(Ri/Ro)**3 )

    @property
    def Asx(self): #Shear Area for tubular cross-section
        return self.Asy

    @property
    def BdgMxx(self):  #Bending modulus for tubular cross-section
        return self.Jxx / (self.D/2)

    @property
    def BdgMyy(self):  #Bending modulus for tubular cross-section =BdgMxx
        return self.Jyy / (self.D/2)

    @property
    def TorsConst(self):  #Torsion shear constant for tubular cross-section
        return self.J0 / (self.D/2)


def vonMises(axial_stress, hoop_stress, shear_stress):
    # von mises stress
    a = ((axial_stress + hoop_stress)/2.0)**2
    b = ((axial_stress - hoop_stress)/2.0)**2
    c = shear_stress**2
    von_mises = np.sqrt(a + 3.0*(b+c))
    return von_mises



def run(D, t, L, tilt, F_hub, M_hub):
    
    # ------- node data ----------------
    n     = 15
    inode = np.arange(1, n+1)
    ynode = znode = rnode = np.zeros(n)
    # Assumption is that x=0 is connection to generator/gearbox, x=L is at hub flange
    xnode = np.linspace(0.0, L, n)
    imb1  = inode[n-1] # Adjust index of where first main bearing is located #
    imb2  = inode[n-11] # Adjust index of where second main bearing is located 
    itorq = inode[0] # First node is generator / gearbox
    nodes = frame3dd.NodeData(inode, xnode, ynode, znode, rnode)
    # ------------------------------------

    # ------ reaction data ------------
    # Reactions at main bearings and at generator/gearbox
    rnode = np.r_[imb1, itorq]
    Rx  = np.array([RIGID, FREE])
    Ry  = np.array([RIGID, FREE])
    Rz  = np.array([RIGID, FREE])
    Rxx = np.array([FREE, RIGID])
    Ryy = np.array([RIGID, FREE])
    Rzz = np.array([RIGID, FREE])
    reactions_1mb = frame3dd.ReactionData(rnode, Rx, Ry, Rz, Rxx, Ryy, Rzz, rigid=RIGID)

    rnode = np.r_[imb1, imb2, itorq]
    Rx  = np.array([RIGID, FREE, FREE]) # Upwind bearing axial restriction
    Ry  = np.array([RIGID, RIGID, FREE]) # Upwind bearing restricts translational
    Rz  = np.array([RIGID, RIGID, FREE]) # Upwind bearing restricts translational
    Rxx = np.array([FREE,  FREE, RIGID]) # Torque is absorbed by stator, so this is the best way to capture that
    Ryy = np.array([FREE,  FREE, FREE]) # 
    Rzz = np.array([FREE,  FREE, FREE]) # 
    reactions_2mb = frame3dd.ReactionData(rnode, Rx, Ry, Rz, Rxx, Ryy, Rzz, rigid=RIGID)
    
    # -----------------------------------

    # ------ frame element data ------------
    myones   = np.ones(n-1)
    shaft    = Tube(D*myones, t*myones)
    ielement = np.arange(1, n)
    N1       = np.arange(1, n)
    N2       = np.arange(2, n+1)
    roll     = np.zeros(n-1)
    Ax = shaft.Area
    As = shaft.Asx
    S  = shaft.BdgMxx
    C  = shaft.TorsConst
    J0 = shaft.J0
    Jx = shaft.Jxx
    elements = frame3dd.ElementData(ielement, N1, N2, Ax, As, As, J0, Jx, Jx,
                                    Steel.E*myones, Steel.G*myones, roll, Steel.rho*myones)
    # -----------------------------------

    # ------ options ------------
    shear = geom = True
    dx = -1
    options = frame3dd.Options(shear, geom, dx)
    # -----------------------------------

    # initialize frameDD3 object
    myframe_1mb = frame3dd.Frame(nodes, reactions_1mb, elements, options)
    myframe_2mb = frame3dd.Frame(nodes, reactions_2mb, elements, options)

    # ------ static load cases ------------
    tilt_r = np.deg2rad(tilt)
    gy = 0.0
    gx = -gravity*np.sin(tilt_r)
    gz = -gravity*np.cos(tilt_r)

    # gravity in the X, Y, Z, directions (global)
    load = frame3dd.StaticLoadCase(gx, gy, gz)

    # point loads
    load.changePointLoads([inode[-1]], [F_hub[0]], [F_hub[1]], [F_hub[2]],
                          [M_hub[0]], [M_hub[1]], [M_hub[2]])
    # -----------------------------------

    # Put all together and run
    myframe_1mb.addLoadCase(load)
    myframe_2mb.addLoadCase(load)

    # NO MODAL ANALYSIS
    for iframe, myframe in enumerate([myframe_1mb, myframe_2mb]):
        displacements, forces, reactions, internalForces, mass3dd, modal = myframe.run()

        # shear and bending, one per element (convert from local to global c.s.)
        iCase = 0

        Fx =  forces.Nx[iCase, 1::2]
        Vy =  forces.Vy[iCase, 1::2]
        Vz = -forces.Vz[iCase, 1::2]
        F  =  np.sqrt(Vz**2 + Vy**2)

        Mxx =  forces.Txx[iCase, 1::2]
        Myy =  forces.Myy[iCase, 1::2]
        Mzz = -forces.Mzz[iCase, 1::2]
        M   =  np.sqrt(Myy**2 + Mzz**2)

        # Record total forces and moments
        F_mb1   = -1.0 * np.array([reactions.Fx[iCase,0], reactions.Fy[iCase,0], reactions.Fz[iCase,0]])
        M_mb1   = -1.0 * np.array([reactions.Mxx[iCase,0], reactions.Myy[iCase,0], reactions.Mzz[iCase,0]])
        if iframe > 0:
            F_mb2   = -1.0 * np.array([reactions.Fx[iCase,1], reactions.Fy[iCase,1], reactions.Fz[iCase,1]])
            M_mb2   = -1.0 * np.array([reactions.Mxx[iCase,1], reactions.Myy[iCase,1], reactions.Mzz[iCase,1]])
        F_torq  = -1.0 * np.array([reactions.Fx[iCase,-1], reactions.Fy[iCase,-1], reactions.Fz[iCase,-1]])
        M_torq  = -1.0 * np.array([reactions.Mxx[iCase,-1], reactions.Myy[iCase,-1], reactions.Mzz[iCase,-1]])
        axial_stress = np.abs(Fx)/Ax + M/S
        shear_stress = 2.0*F/As + np.abs(Mxx)/C
        hoop = np.zeros(F.shape)

        vonmises = vonMises(axial_stress, hoop, shear_stress)
       # print('\tShaft stress',vonmises)
       # print('\tForces on main bearing 1:',F_mb1.tolist())
    #    print('\tMoment on main bearing 1:',M_mb1.tolist())
       # if iframe > 0:
          #  print('\tForces on main bearing 2:',F_mb2.tolist())
          # print('\tMoment on main bearing 2:',M_mb2.tolist())
       # print('\tForces on generator / gearbox:',F_torq.tolist())
       # print('\tMoment on generator / gearbox:',M_torq.tolist())
    return F_mb1, F_mb2



if __name__ == '__main__':
    
    import filetranslation
    #Define load channel inputs
    Data = filetranslation.Filetranslation()
    data, ChanName, info = Data.load_binary_output("5MWFastData.outb")
    rot_speed = data[:3000,7] 
    torque = data[:3000,5] * 1E3 # in N-m
    RotThrust = data[:3000,6] * 1E3 # in N
    m_y = data[:3000,8] * 1E3 # in N-m
    m_z = data[:3000,9] * 1E3 # in N-m
    f_y = data[:3000,10] * 1E3 # in N
    f_z = data[:3000,11] * 1E3 
    
    # Shaft specs
    diameter  = 0.75 # m
    thickness = 0.25 # m
    length    = 3 # m
    tilt      = 5 # deg

    # Hub forces & moments
    # (start with pure torque)
    i=0
    f_r1v = []
    f_r2v = []
    f_a1v = []
    f_total1v = []
    
    
    while i<3000:
        F_hub = [-RotThrust[i] + m_rh*g*np.sin(rho) + m_gr*g*np.sin(rho) + m_s*g*np.sin(rho), f_y[i], m_rh*g*np.cos(rho)]
        M_hub = [torque[i],m_y[i],m_z[i]]
        # Run Frame3DD and print results to screen
        F_mb1, F_mb2 = run(diameter, thickness, length, tilt, F_hub, M_hub)
        f_r1v.append((F_mb1[1]**2 + F_mb1[2]**2)**0.5)
        f_r2v.append((F_mb2[1]**2 + F_mb2[2]**2)**0.5)
        f_a1v.append(F_mb1[0])
        f_total1v.append(1.2*f_r1v[i] + 0.39*F_mb1[0])
        i=i+1
        
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
        
    L101, L10_total_MB1 = MainBearingCalc.L10_Calc(rot_speed, f_total1v)
    L102, L10_total_MB2 = MainBearingCalc.L10_Calc(rot_speed, f_r2v)

print('MB1 L10 Calculated: ', L10_total_MB1, "hours or", L10_total_MB1/24/365 , "years" )
print('MB2 L10 Calculated: ', L10_total_MB2, "hours or", L10_total_MB2/24/365 , "years" )