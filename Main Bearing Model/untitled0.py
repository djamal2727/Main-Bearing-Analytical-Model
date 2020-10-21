# -*- coding: utf-8 -*-
"""
Created on Mon Oct 19 09:48:45 2020

@author: djamal
"""

import numpy as np
import numpy.testing as npt
import unittest
import wisdem.drivetrainse.drive_structure as ds
import wisdem.drivetrainse.layout as lay
from wisdem.commonse import gravity

npts = 10

class TestDirectStructure(unittest.TestCase):
    def setUp(self):
        self.inputs = {}
        self.outputs = {}
        self.discrete_inputs = {}
        self.discrete_outputs = {}
        self.opt = {}

        self.discrete_inputs['upwind'] = True

        self.inputs['L_12'] = 2.0
        self.inputs['L_h1'] = 1.0
        self.inputs['L_generator'] = 3.25
        #self.inputs['L_2n'] = 1.5
        #self.inputs['L_grs'] = 1.1
        #self.inputs['L_gsn'] = 1.1
        self.inputs['L_hss'] = 0.75
        self.inputs['L_gearbox'] = 1.2
        self.inputs['overhang'] = 6.25
        self.inputs['drive_height'] = 4.875
        self.inputs['tilt'] = 4.0
        self.inputs['access_diameter'] = 0.9

        myones = np.ones(5)
        self.inputs['lss_diameter'] = 3.3*myones
        self.inputs['lss_wall_thickness'] = 0.45*myones
        self.inputs['hss_diameter'] = 1.6*np.ones(3)
        self.inputs['hss_wall_thickness'] = 0.25*np.ones(3)
        self.inputs['nose_diameter'] = 2.2*myones
        self.inputs['nose_wall_thickness'] = 0.1*myones
        self.inputs['bedplate_wall_thickness'] = 0.06*np.ones(npts)

        self.inputs['bedplate_flange_width'] = 1.5
        self.inputs['bedplate_flange_thickness'] = 0.05
        #self.inputs['bedplate_web_height'] = 1.0
        self.inputs['bedplate_web_thickness'] = 0.05

        self.inputs['D_top'] = 6.5

        self.inputs['other_mass'] = 200e3
        self.inputs['mb1_mass'] = 10e3
        self.inputs['mb1_I'] = 10e3*0.5*2**2*np.ones(3)
        self.inputs['mb2_mass'] = 10e3
        self.inputs['mb2_I'] = 10e3*0.5*1.5**2*np.ones(3)
        self.inputs['mb1_max_defl_ang'] = 0.008
        self.inputs['mb2_max_defl_ang'] = 0.008

        self.inputs['m_stator'] = 100e3
        self.inputs['cm_stator'] = -0.3
        self.inputs['I_stator'] = np.array([1e6, 5e5, 5e5, 0.0, 0.0, 0.0])
        
        self.inputs['m_rotor'] = 100e3
        self.inputs['cm_rotor'] = -0.3
        self.inputs['I_rotor'] = np.array([1e6, 5e5, 5e5, 0.0, 0.0, 0.0])

        self.inputs['generator_mass'] = 200e3
        self.inputs['generator_I'] = np.array([2e6, 1e6, 1e6, 0.0, 0.0, 0.0])

        self.inputs['gearbox_mass'] = 100e3
        self.inputs['gearbox_I'] = np.array([1e6, 5e5, 5e5, 0.0, 0.0, 0.0])

        self.inputs['brake_mass'] = 10e3
        self.inputs['brake_I'] = np.array([1e4, 5e3, 5e3])

        self.inputs['gear_ratio'] = 1.0
        
        self.inputs['F_mb1'] = np.array([2409.750e3, -1716.429e3, 74.3529e3]).reshape((3,1))
        self.inputs['F_mb2'] = np.array([2409.750e3, -1716.429e3, 74.3529e3]).reshape((3,1))
        self.inputs['M_mb1'] = np.array([-1.83291e7, 6171.7324e3, 5785.82946e3]).reshape((3,1))
        self.inputs['M_mb2'] = np.array([-1.83291e7, 6171.7324e3, 5785.82946e3]).reshape((3,1))

        self.inputs['hub_system_mass'] = 100e3
        self.inputs['hub_system_cm'] = 2.0
        self.inputs['hub_system_I'] = np.array([2409.750e3, -1716.429e3, 74.3529e3, 0.0, 0.0, 0.0])
        self.inputs['F_hub'] = np.array([2409.750e3, 0.0, 74.3529e2]).reshape((3,1))
        self.inputs['M_hub'] = np.array([-1.83291e4, 6171.7324e2, 5785.82946e2]).reshape((3,1))
        
        self.inputs['lss_E'] = self.inputs['hss_E'] = self.inputs['bedplate_E'] = 210e9
        self.inputs['lss_G'] = self.inputs['hss_G'] = self.inputs['bedplate_G'] = 80.8e9
        self.inputs['lss_rho'] = self.inputs['hss_rho'] = self.inputs['bedplate_rho'] = 7850.
        self.inputs['lss_Xy'] = self.inputs['hss_Xy'] = self.inputs['bedplate_Xy'] = 250e6

        self.opt['gamma_f'] = 1.35
        self.opt['gamma_m'] = 1.3
        self.opt['gamma_n'] = 1.0

    def compute_layout(self, direct=True):
        myobj = lay.DirectLayout(n_points=npts) if direct else lay.GearedLayout()
        myobj.compute(self.inputs, self.outputs, self.discrete_inputs, self.discrete_outputs)
        for k in self.outputs.keys():
            self.inputs[k] = self.outputs[k]
        
    def testRunRotatingDirect_withTilt(self):
        self.inputs['tilt'] = 5.0
        self.inputs['F_hub'] = np.zeros(3).reshape((3,1))
        self.inputs['M_hub'] = np.zeros(3).reshape((3,1))
        self.compute_layout()
        myobj = ds.Hub_Rotor_LSS_Frame(n_dlcs=1, modeling_options=self.opt, direct_drive=True)
        myobj.compute(self.inputs, self.outputs, self.discrete_inputs, self.discrete_outputs)
        F0 = self.outputs['F_mb1'].flatten()
        M0 = self.outputs['M_mb2'].flatten()
        self.assertGreater(0.0, F0[0])
        self.assertGreater(0.0, F0[-1])
        #self.assertGreater(0.0, M0[1])
        npt.assert_almost_equal(self.outputs['F_mb1'][1], 0.0, decimal=2)
        npt.assert_almost_equal(self.outputs['F_mb2'], 0.0, decimal=2)
        npt.assert_almost_equal(self.outputs['F_torq'], 0.0, decimal=2)
        npt.assert_almost_equal(self.outputs['M_mb1'], 0.0, decimal=2)
        npt.assert_almost_equal(self.outputs['M_mb2'][[0,2]], 0.0, decimal=2)
        npt.assert_almost_equal(self.outputs['M_torq'], 0.0, decimal=2)

        g = np.array([30e2, 40e2, 50e2])
        self.inputs['F_hub'] = g.reshape((3,1))
        self.inputs['M_hub'] = 2*g.reshape((3,1))
        myobj.compute(self.inputs, self.outputs, self.discrete_inputs, self.discrete_outputs)
        npt.assert_almost_equal(self.outputs['F_mb1'].flatten(), g+F0, decimal=2)
        npt.assert_almost_equal(self.outputs['F_mb2'], 0.0, decimal=2)
        npt.assert_almost_equal(self.outputs['F_torq'], 0.0, decimal=2)
        npt.assert_almost_equal(self.outputs['M_mb1'], 0.0, decimal=2)
        npt.assert_almost_equal(self.outputs['M_mb2'].flatten()[0], 0.0, decimal=2)
        npt.assert_almost_equal(self.outputs['M_mb2'].flatten()[1], g[-1]*1+2*g[1]+M0[1], decimal=1) #*1=*L_h1
        npt.assert_almost_equal(self.outputs['M_mb2'].flatten()[2], -g[1]*1+2*g[2], decimal=1) #*1=*L_h1
        npt.assert_almost_equal(self.outputs['M_torq'].flatten(), np.r_[2*g[0], 0.0, 0.0], decimal=2)
        
        
def suite():
    suite = unittest.TestSuite()
    suite.addTest(unittest.makeSuite(TestDirectStructure))
    return suite


if __name__ == '__main__':
    unittest.TextTestRunner().run(suite())
