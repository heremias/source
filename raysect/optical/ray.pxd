# cython: language_level=3

#Copyright (c) 2014, Dr Alex Meakins, Raysect Project
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     1. Redistributions of source code must retain the above copyright notice,
#        this list of conditions and the following disclaimer.
#
#     2. Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in the
#        documentation and/or other materials provided with the distribution.
#
#     3. Neither the name of the Raysect Project nor the names of its
#        contributors may be used to endorse or promote products derived from
#        this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

from raysect.core.classes cimport Ray
from raysect.core.math.point cimport Point
from raysect.core.math.vector cimport Vector
from raysect.core.scenegraph.world cimport World

cdef class Waveband:

    cdef double _min_wavelength
    cdef double _max_wavelength

    cpdef Waveband copy(self)

    cdef inline double get_min_wavelength(self)

    cdef inline double get_max_wavelength(self)


cdef inline Waveband new_waveband(double min_wavelength, double max_wavelength):

    cdef Waveband w

    w = Waveband.__new__(Waveband)
    w._min_wavelength = min_wavelength
    w._max_wavelength = max_wavelength

    return w


cdef class RayResponce:

    pass


cdef class OpticalRay(Ray):

    cdef readonly OpticalRay primary_ray
    cdef double _refraction_wavelength
    cdef list _wavebands
    cdef readonly bint cache_valid

    cpdef append_waveband(self, Waveband waveband)

    cpdef object trace(self, World world)

    cpdef Ray spawn_daughter(self, Point origin, Vector direction)

    cdef inline double get_refraction_wavelength(self)

    cdef inline int get_waveband_count(self)

    cdef inline Waveband get_waveband(self, int index)

