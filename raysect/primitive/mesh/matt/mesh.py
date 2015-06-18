
# Largely a copy of the mesh object from numpy
# https://pypi.python.org/pypi/numpy-stl

import numpy
from numpy import cross, sqrt

#: When removing empty areas, remove areas that are smaller than this
AREA_SIZE_THRESHOLD = 0
#: Vectors in a point
VECTORS = 3
#: Dimensions used in a vector
DIMENSIONS = 3
#: X index (for example, `mesh.v0[0][X]`)
X = 0
#: Y index (for example, `mesh.v0[0][Y]`)
Y = 1
#: Z index (for example, `mesh.v0[0][Z]`)
Z = 2


class Mesh():
    """
    Mesh object with easy access to the vectors through v0, v1 and v2.
    The normals, areas, min, max and units are calculated automatically.

    :param numpy.array data: The data for this mesh
    :param bool calculate_normals: Whether to calculate the normals
    :param bool remove_empty_areas: Whether to remove triangles with 0 area
            (due to rounding errors for example)

    :ivar str name: Name of the solid, only exists in ASCII files
    :ivar numpy.array data: Data as :func:`BaseMesh.dtype`
    :ivar numpy.array points: All points (Nx9)
    :ivar numpy.array normals: Normals for this mesh, calculated automatically
        by default (Nx3)
    :ivar numpy.array vectors: Vectors in the mesh (Nx3x3)
    :ivar numpy.array attr: Attributes per vector (used by binary STL)
    :ivar numpy.array x: Points on the X axis by vertex (Nx3)
    :ivar numpy.array y: Points on the Y axis by vertex (Nx3)
    :ivar numpy.array z: Points on the Z axis by vertex (Nx3)
    :ivar numpy.array v0: Points in vector 0 (Nx3)
    :ivar numpy.array v1: Points in vector 1 (Nx3)
    :ivar numpy.array v2: Points in vector 2 (Nx3)
    """

    def __init__(self, data, calculate_normals=True,
                 remove_empty_areas=False, remove_duplicate_polygons=False, name='', **kwargs):

        if remove_empty_areas:
            data = self.remove_empty_areas(data)

        if remove_duplicate_polygons:
            data = self.remove_duplicate_polygons(data)

        self.name = name
        self.data = data

        points = self.points = data['vectors']
        self.points.shape = data.size, 9
        self.x = points[:, X::3]
        self.y = points[:, Y::3]
        self.z = points[:, Z::3]
        self.v0 = data['vectors'][:, 0]
        self.v1 = data['vectors'][:, 1]
        self.v2 = data['vectors'][:, 2]
        self.normals = data['normals']
        self.vectors = data['vectors']
        self.attr = data['attr']

        if calculate_normals:
            self.update_normals()

    @classmethod
    def remove_duplicate_polygons(cls, data):
        polygons = data['vectors'].sum(axis=1)
        # Get a sorted list of indices
        idx = numpy.lexsort(polygons.T)
        # Get the indices of all different indices
        diff = numpy.any(polygons[idx[1:]] != polygons[idx[:-1]], axis=1)
        # Only return the unique data, the True is so we always get at least
        # the originals
        return data[numpy.sort(idx[numpy.concatenate(([True], diff))])]

    @classmethod
    def remove_empty_areas(cls, data):
        vectors = data['vectors']
        v0 = vectors[:, 0]
        v1 = vectors[:, 1]
        v2 = vectors[:, 2]
        normals = cross(v1 - v0, v2 - v0)
        areas = sqrt((normals ** 2).sum(axis=1))
        return data[areas > AREA_SIZE_THRESHOLD]

    def update_normals(self):
        '''Update the normals for all points'''
        self.normals[:] = cross(self.v1 - self.v0, self.v2 - self.v0)

    def update_min(self):
        self._min = self.vectors.min(axis=(0, 1))

    def update_max(self):
        self._max = self.vectors.max(axis=(0, 1))

    def update_areas(self):
        areas = .5 * sqrt((self.normals ** 2).sum(axis=1))
        self.areas = areas.reshape((areas.size, 1))

    def update_units(self):
        units = self.normals.copy()
        non_zero_areas = self.areas > 0
        areas = self.areas

        if non_zero_areas.shape[0] != areas.shape[0]:  # pragma: no cover
            self.warning('Zero sized areas found, '
                         'units calculation will be partially incorrect')

        if non_zero_areas.any():
            non_zero_areas.shape = non_zero_areas.shape[0]
            areas = numpy.hstack((2 * areas[non_zero_areas],) * DIMENSIONS)
            units[non_zero_areas] /= areas

        self.units = units

    def _get_or_update(key):
        def _get(self):
            if not hasattr(self, '_%s' % key):
                getattr(self, 'update_%s' % key)()
            return getattr(self, '_%s' % key)

        return _get

    def _set(key):
        def _set(self, value):
            setattr(self, '_%s' % key, value)

        return _set

    min_ = property(_get_or_update('min'), _set('min'),
                    doc='Mesh minimum value')
    max_ = property(_get_or_update('max'), _set('max'),
                    doc='Mesh maximum value')
    areas = property(_get_or_update('areas'), _set('areas'),
                     doc='Mesh areas')
    units = property(_get_or_update('units'), _set('units'),
                     doc='Mesh unit vectors')

    def __getitem__(self, k):
        return self.points[k]

    def __setitem__(self, k, v):
        self.points[k] = v

    def __len__(self):
        return self.points.shape[0]

    def __iter__(self):
        for point in self.points:
            yield point


