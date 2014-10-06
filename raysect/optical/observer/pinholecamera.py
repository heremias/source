# Copyright (c) 2014, Dr Alex Meakins, Raysect Project
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

from time import time
from numpy import array, zeros
from math import sin, cos, tan, atan, pi
from matplotlib.pyplot import imshow, imsave, show, ion, ioff, clf, figure, draw, pause
from raysect.optical.ray import Ray
from raysect.optical import Spectrum
from raysect.core import World, AffineMatrix, Point, Vector, Observer
from raysect.optical.colour import resample_ciexyz, spectrum_to_ciexyz, ciexyz_to_srgb


class PinholeCamera(Observer):

    def __init__(self, pixels=(640, 480), fov = 40, spectral_samples = 20, rays = 1, parent = None, transform = AffineMatrix(), name = ""):

        super().__init__(parent, transform, name)

        self.pixels = pixels
        self.fov = fov
        self.frame = zeros((pixels[1], pixels[0], 3))
        # self.subsampling = 1

        self.rays = rays
        self.spectral_samples = spectral_samples

        self.min_wavelength = 375.0
        self.max_wavelength = 740.0

        self.ray_max_depth = 15

        self.display_progress = True
        self.display_update_time = 10.0


    @property
    def pixels(self):

        return self._pixels

    @pixels.setter
    def pixels(self, pixels):

        if len(pixels) != 2:

            raise ValueError("Pixel dimensions of camera framebuffer must be a tuple containing the x and y pixel counts.")

        self._pixels = pixels

    @property
    def fov(self):

        return self._fov

    @fov.setter
    def fov(self, fov):

        if fov <= 0:

            raise ValueError("Field of view angle can not be less than or equal to 0 degrees.")

        self._fov = fov

    def observe(self):

        xyz_frame = zeros((self._pixels[1], self._pixels[0], 3))
        self.frame = zeros((self._pixels[1], self._pixels[0], 3))

        if not isinstance(self.root, World):

            raise TypeError("Observer is not connected to a scene graph containing a World object.")

        world = self.root

        max_pixels = max(self._pixels)

        if max_pixels > 1:

            # max width of image plane at 1 meter
            image_max_width = 2 * tan(pi / 180 * 0.5 * self._fov)

            # pixel step and start point in image plane
            image_delta = image_max_width / (max_pixels - 1)

            # start point of scan in image plane
            image_start_x = 0.5 * self._pixels[0] * image_delta
            image_start_y = 0.5 * self._pixels[1] * image_delta

        else:

            # single ray on axis
            image_delta = 0
            image_start_x = 0
            image_start_y = 0

        total_samples = self.rays * self.spectral_samples

        resampled_xyz = resample_ciexyz(self.min_wavelength,
                                        self.max_wavelength,
                                        total_samples)

        # generate rays
        rays = list()
        delta_wavelength = (self.max_wavelength - self.min_wavelength) / self.rays
        lower_wavelength = self.min_wavelength
        for index in range(self.rays):

            upper_wavelength = self.min_wavelength + delta_wavelength * (index + 1)

            rays.append(Ray(min_wavelength=lower_wavelength,
                            max_wavelength=upper_wavelength,
                            num_samples=self.spectral_samples,
                            max_depth=self.ray_max_depth))

            lower_wavelength = upper_wavelength

        # initialise statistics
        total_pixels = self._pixels[0] * self._pixels[1]
        total_work = total_pixels * self.rays
        ray_count = 0
        start_time = time()
        progress_timer = time()

        display_timer = 0
        if self.display_progress:

            self.display()
            display_timer = time()

        lower_index = 0
        for index, ray in enumerate(rays):

            upper_index = self.spectral_samples * (index + 1)

            for y in range(0, self._pixels[1]):

                for x in range(0, self._pixels[0]):

                    # display progress statistics
                    dt = time() - progress_timer
                    if dt > 1.0:

                        current_pixel = y * self._pixels[0] + x
                        current_work = self._pixels[0] * self._pixels[1] * index + current_pixel
                        completion = 100 * current_work / total_work
                        rays_per_second = ray_count / (1000 * dt)
                        print("{:0.2f}% complete (channel {}/{}, line {}/{}, pixel {}/{}, {:0.1f}k rays/s)".format(
                            completion, index + 1, len(rays), y, self._pixels[1], current_pixel, total_pixels, rays_per_second))
                        ray_count = 0
                        progress_timer = time()

                    # calculate ray parameters
                    origin = Point(0, 0, 0)
                    direction = Vector(image_start_x - image_delta * x, image_start_y - image_delta * y, 1.0).normalise()

                    # convert to world space
                    origin = origin.transform(self.to_root())
                    direction = direction.transform(self.to_root())

                    # sample world
                    spectrum = Spectrum(self.min_wavelength, self.max_wavelength, total_samples)

                    ray.origin = origin
                    ray.direction = direction

                    sample = ray.trace(world)
                    spectrum.samples[lower_index:upper_index] = sample.samples

                    # collect ray statistics
                    ray_count += ray.ray_count

                    # convert spectrum to CIE XYZ and accumulate
                    xyz = spectrum_to_ciexyz(spectrum, resampled_xyz)
                    xyz_frame[y, x, 0] += xyz[0]
                    xyz_frame[y, x, 1] += xyz[1]
                    xyz_frame[y, x, 2] += xyz[2]

                    # update display image
                    self.frame[y, x, :] = ciexyz_to_srgb(*xyz_frame[y, x, :])

                    if self.display_progress and (time() - display_timer) > self.display_update_time:

                        print("Refreshing display...")
                        self.display()
                        display_timer = time()

            lower_index = upper_index

        # close statistics
        elapsed_time = time() - start_time
        print("Render complete - time elapsed {:0.3f}s".format(elapsed_time))

        if self.display_progress:

            self.display()

    def display(self):

        clf()
        imshow(self.frame, aspect="equal", origin="upper")
        draw()
        show()

    def save(self, filename):

        imsave(filename, self.frame)

