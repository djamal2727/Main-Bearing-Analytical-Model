from collections import namedtuple
import numpy as np
import pyframe3dd.pyframe3dd as frame3dd

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



def run(D, t, L, tilt, F_hub, M_hub, npts):
    
    # ------- node data ----------------
    n     = npts
    inode = np.arange(1, n+1)
    ynode = znode = rnode = np.zeros(n)
    # Assumption is that x=0 is connection to generator/gearbox, x=L is at hub flange
    xnode = np.linspace(0.0, L, npts)
    imb   = inode[n-2] # Adjust index of where main bearing is located
    itorq = inode[0] # First node is generator / gearbox
    nodes = frame3dd.NodeData(inode, xnode, ynode, znode, rnode)
    # ------------------------------------

    # ------ reaction data ------------
    # Reactions at main bearings and at generator/gearbox
    rnode = np.r_[imb, itorq]
    Rx  = np.array([RIGID, FREE]) # Upwind bearing restricts translational
    Ry  = np.array([RIGID, FREE]) # Upwind bearing restricts translational
    Rz  = np.array([RIGID, FREE]) # Upwind bearing restricts translational
    Rxx = np.array([FREE, RIGID]) # Torque is absorbed by stator, so this is the best way to capture that
    Ryy = np.array([RIGID, FREE]) # downwind bearing carry moments
    Rzz = np.array([RIGID, FREE]) # downwind bearing carry moments
    reactions = frame3dd.ReactionData(rnode, Rx, Ry, Rz, Rxx, Ryy, Rzz, rigid=RIGID)
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
    myframe = frame3dd.Frame(nodes, reactions, elements, options)

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
    myframe.addLoadCase(load)

    # NO MODAL ANALYSIS
    
    #myframe.write('myframe2.3dd') # Debugging
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
    F_torq  = -1.0 * np.array([reactions.Fx[iCase,1], reactions.Fy[iCase,1], reactions.Fz[iCase,1]])
    M_mb1   = -1.0 * np.array([reactions.Mxx[iCase,0], reactions.Myy[iCase,0], reactions.Mzz[iCase,0]])
    M_torq  = -1.0 * np.array([reactions.Mxx[iCase,1], reactions.Myy[iCase,1], reactions.Mzz[iCase,1]])
    axial_stress = np.abs(Fx)/Ax + M/S
    shear_stress = 2.0*F/As + np.abs(Mxx)/C
    hoop = np.zeros(F.shape)

    vonmises = vonMises(axial_stress, hoop, shear_stress)
    print('Shaft stress',vonmises)
    print('Forces on main bearing:',F_mb1.tolist())
    print('Moment on main bearing:',M_mb1.tolist())
    print('Forces on generator / gearbox:',F_torq.tolist())
    print('Moment on generator / gearbox:',M_torq.tolist())

    
# if __name__ == '__main__':
# Shaft specs'=
diameter  = 0.5 # m
thickness = 0.1 # m
length    = 3.0 # m
tilt      = 5.0 # deg
    
    # Hub forces & moments
    # (start with pure torque)
F_hub = np.zeros(3)
M_hub = np.zeros(3)
M_hub[0] = 1e6 # N-m

    # Number of discretization points
npts = 10

    # Run Frame3DD and print results to screen
run(diameter, thickness, length, tilt, F_hub, M_hub, npts)
