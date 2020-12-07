# -*- coding: utf-8 -*-
"""
Created on Mon Nov 23 07:11:14 2020

@author: djamal
"""
import numpy as np


a = [1,2,3]
a1 = np.array(a)
b = [4,5,6]
b1 = np.array(b)

from sklearn.metrics import mean_squared_error
from math import sqrt

rms = sqrt(mean_squared_error(a1, b1))

print(rms)