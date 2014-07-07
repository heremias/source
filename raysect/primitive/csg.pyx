# cython: language_level=3

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

from raysect.core.classes cimport Ray, Intersection, Material
from raysect.core.math.point cimport Point, new_point
from raysect.core.math.affinematrix cimport AffineMatrix
from raysect.core.acceleration.boundingbox cimport BoundingBox
from raysect.core.scenegraph._nodebase cimport _NodeBase

# bounding box is padded by a small amount to avoid numerical accuracy issues
DEF BOX_PADDING = 1e-9

# cython doesn't have a built in infinity definition
DEF INFINITY = 1e999

cdef class CSGPrimitive(Primitive):

    def __init__(self, object parent = None, AffineMatrix transform not None = AffineMatrix(), Material material not None = Material(), Primitive primitive_a not None = NullPrimitive(), Primitive primitive_b not None = NullPrimitive(), unicode name not None= ""):

        super().__init__(parent, transform, material, name)

        # wrap primitives in bounding boxes
        # this must be done before building the scenegraph as re-parenting
        # triggers rebuild() on the new root node
        self._primitive_a = AcceleratedPrimitive(primitive_a)
        self._primitive_b = AcceleratedPrimitive(primitive_b)

        # build CSG scene graph
        self._root = CSGRoot(self)
        primitive_a.parent = self._root
        primitive_b.parent = self._root

    property primitive_a:

        def __get__(self):

            return self._primitive_a.primitive

        def __set__(self, Primitive primitive not None):

            # remove old primitive from scenegraph
            self._primitive_a.primitive.parent = None

            # insert new primitive into scenegraph
            self._primitive_a = AcceleratedPrimitive(primitive)
            primitive.parent = self._root

    property primitive_b:

        def __get__(self):

            return self._primitive_b.primitive

        def __set__(self, Primitive primitive not None):

            # remove old primitive from scenegraph
            self._primitive_b.primitive.parent = None

            # insert new primitive into scenegraph
            self._primitive_b = AcceleratedPrimitive(primitive)
            primitive.parent = self._root

    cpdef BoundingBox bounding_box(self):

        cdef:
            list points
            Point point
            BoundingBox box

        box = BoundingBox()

        # combine local space bounding boxes
        box.union(self._primitive_a.box)
        box.union(self._primitive_b.box)

        # convert box vertices to world space
        points = [
            box.lower.transform(self.to_root()),
            new_point(box.lower.x, box.lower.y, box.upper.z).transform(self.to_root()),
            new_point(box.lower.x, box.upper.y, box.lower.z).transform(self.to_root()),
            new_point(box.lower.x, box.upper.y, box.upper.z).transform(self.to_root()),
            new_point(box.upper.x, box.lower.y, box.lower.z).transform(self.to_root()),
            new_point(box.upper.x, box.lower.y, box.upper.z).transform(self.to_root()),
            new_point(box.upper.x, box.upper.y, box.lower.z).transform(self.to_root()),
            box.upper.transform(self.to_root())
            ]

        # build new world space bounding box that enclose all points
        # a small degree of padding is added to avoid potential numerical accuracy issues
        box = BoundingBox()
        for point in points:

            box.lower.x = min(box.lower.x, point.x - BOX_PADDING)
            box.lower.y = min(box.lower.y, point.y - BOX_PADDING)
            box.lower.z = min(box.lower.z, point.z - BOX_PADDING)

            box.upper.x = max(box.upper.x, point.x + BOX_PADDING)
            box.upper.y = max(box.upper.y, point.y + BOX_PADDING)
            box.upper.z = max(box.upper.z, point.z + BOX_PADDING)

        return box

    cdef void rebuild(self):
        """
        Triggers a rebuild of the CSG primitive's acceleration structures.
        """

        self._primitive_a = AcceleratedPrimitive(self._primitive_a.primitive)
        self._primitive_b = AcceleratedPrimitive(self._primitive_b.primitive)


cdef class NullPrimitive(Primitive):
    """
    Dummy primitive class.

    The _CSGPrimitive base class requires a primitive that returns a valid bounding box.
    This class overrides the bounding_box method to return an empty bounding box.
    This class is intended to act as a place holder until a user sets a valid primitive.
    """

    cpdef BoundingBox bounding_box(self):

        return BoundingBox()


cdef class CSGRoot(Node):
    """
    Specialised scenegraph root node for CSG primitives.

    The root node responds to geometry change notifications and propagates them
    to the CSG primitive and its enclosing scenegraph.
    """

    def __init__(self, CSGPrimitive csg_primitive):

        super().__init__()
        self.csg_primitive = csg_primitive

    def _change(self, _NodeBase node):
        """
        Handles a scenegraph node change handler.

        Propagates geometry change notifications to the enclosing CSG primitive and its
        scenegraph.
        """

        # the CSG primitive acceleration structures must be rebuilt
        self.csg_primitive.rebuild()

        # propagate geometry change notification from csg scenegraph to enclosing scenegraph
        self.csg_primitive.notify_root()


cdef class Union(CSGPrimitive):

    cpdef Intersection hit(self, Ray ray):

        cdef:
            Ray local_ray
            Intersection intersection_a, intersection_b, closest_intersection

        # convert ray to local space
        local_ray = Ray(ray.origin.transform(self.to_local()),
                        ray.direction.transform(self.to_local()),
                        INFINITY)

        # obtain intersections
        intersection_a = self.primitive_a.hit(local_ray)
        intersection_b = self.primitive_b.hit(local_ray)
        closest_intersection = self._closest_intersection(intersection_a, intersection_b)

        # identify first intersection that satisfies union operator
        while closest_intersection is not None:

            if self._valid_intersection(intersection_a, intersection_b, closest_intersection):

                if closest_intersection.ray_distance <= ray.max_distance:

                    # TODO: cache data for next_intersection()

                    # convert local intersection attributes to csg primitive coordinate space
                    closest_intersection.ray = ray
                    closest_intersection.hit_point = closest_intersection.hit_point.transform(closest_intersection.to_world)
                    closest_intersection.inside_point = closest_intersection.inside_point.transform(closest_intersection.to_world)
                    closest_intersection.outside_point = closest_intersection.outside_point.transform(closest_intersection.to_world)
                    closest_intersection.normal = closest_intersection.normal.transform(closest_intersection.to_world)
                    closest_intersection.to_local = self.to_local()
                    closest_intersection.to_world = self.to_root()
                    closest_intersection.primitive = self

                    # allow derived classes to modify intersection if required
                    return self._update_intersection(closest_intersection)

                else:

                    return None

            # closest intersection was rejected so need a replacement candidate intersection
            # from the primitive that was the source of the closest intersection
            if closest_intersection.primitive is self._primitive_a:

                intersection_a = self._primitive_a.next_intersection()

            else:

                intersection_b = self._primitive_b.next_intersection()

            closest_intersection = self._closest_intersection(intersection_a, intersection_b)

        # no valid intersections
        return None

    cdef inline Intersection _closest_intersection(self, Intersection a, Intersection b):

        if a is None:

            return b

        else:

            if b is None or a.ray_distance < b.ray_distance:

                return a

            else:

                return b

    cdef inline bint _valid_intersection(self, Intersection a, Intersection b, Intersection closest):

        cdef bint inside_a, inside_b

        # determine ray enclosure state prior to intersection
        inside_a = a is not None and a.exiting
        inside_b = b is not None and b.exiting

        # union logic
        if not inside_a and not inside_b:

            # outside the whole object, intersection must be entering the object or entirely missing
            return True

        elif inside_a and not inside_b and closest is a:

            # outside primitive B and leaving primitive A, therefore leaving the unioned object
            return True

        elif not inside_a and inside_b and closest is b:

            # outside primitive A and leaving primitive B, therefore leaving the unioned object
            return True

        # all other intersections are occurring inside unioned object and are therefore invalid
        return False

    cdef inline Intersection _update_intersection(self, Intersection intersection):

        # do nothing
        return intersection

    cpdef Intersection next_intersection(self):

        # TODO: implement me!
        return None

    cpdef bint contains(self, Point p) except -1:

        p = p.transform(self.to_local())

        return self._primitive_a.primitive.contains(p) or self._primitive_b.primitive.contains(p)


cdef class Intersect(CSGPrimitive):

    cpdef Intersection hit(self, Ray ray):

        return None

    cpdef Intersection next_intersection(self):

        # TODO: implement me
        return None

    cpdef bint contains(self, Point p) except -1:

        return False


cdef class Subtract(CSGPrimitive):

    cpdef Intersection hit(self, Ray ray):

        return None

    cpdef Intersection next_intersection(self):

        # TODO: implement me
        return None

    cpdef bint contains(self, Point p) except -1:

        return False