# cython: language_level=3

# Copyright (c) 2014-2018, Dr Alex Meakins, Raysect Project
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

from numpy cimport ndarray
from raysect.optical cimport World, Primitive, Ray, Spectrum, Point3D, Vector3D, AffineMatrix3D, Normal3D, SpectralFunction
from raysect.optical.material.material cimport NullVolume, Material
from libc.math cimport exp
cimport cython


cdef class PlanckEmitter(NullVolume):
    """
    Custom material for modelling thermal emission from hot primitives.

    Uses a given material for reflection model and adds surface emission based on
    a temperature and spectral total emissivity. Use with care, because:
    (a) It does not automatically obey Kirchoff's radiation law (i.e. is not
    energy conserving) because there is no easy way to get the total reflection +
    transmission from the given material: the user should therefore explicitly
    check that the specified emissivity is consistent with 1 - (reflection + transmission)
    if you want energy conservation.
    (b) Currently temperature dependence of the emissivity is not included, but for
    many relevant materials e.g. refractory metals there is a strong dependence in real life.

    :param Material material: Material for reflection model
    :param double temperature: Material surface temperature in degrees C
    :param SpectralFunction eps: IR emissivity as a function of wavelength.
    """

    cdef:
        Material material
        SpectralFunction eps
        double temperature

    def __init__(self, Material material, double temperature, SpectralFunction eps):
        super().__init__()
        self.material = material
        self.temperature = temperature
        self.eps = eps

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.initializedcheck(False)
    cpdef Spectrum evaluate_surface(self, World world, Ray ray, Primitive primitive, Point3D hit_point,
                                    bint exiting, Point3D inside_point, Point3D outside_point,
                                    Normal3D normal, AffineMatrix3D world_to_primitive, AffineMatrix3D primitive_to_world):

        cdef:
            Spectrum reflected_spectrum
            ndarray wl_m
            double ci
            double[::1] n, k
            double h = 6.62607e-34
            double c = 2.99792e8
            double kB = 1.38065e-23
            int i

        reflected_spectrum = self.material.evaluate_surface(
            world, ray, primitive, hit_point, exiting, inside_point, outside_point,
            normal, world_to_primitive, primitive_to_world
        )


        # Emission spectrum
        eps_ = self.eps.sample(ray.min_wavelength,ray.max_wavelength,ray.bins)
        emitted_spectrum = ray.new_spectrum()
        wl_m = emitted_spectrum.wavelengths*1e-9
        for i in range(emitted_spectrum.bins):
            emitted_spectrum.samples_mv[i] = eps_[i] * 2e-9*h*c**2 / ( wl_m[i]**5 * (exp(h*c/(kB*wl_m[i]*(self.temperature+273.15))) - 1) )


        reflected_spectrum.add_array(emitted_spectrum.samples_mv)

        return reflected_spectrum
