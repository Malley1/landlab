import numpy as np
cimport numpy as np
cimport cython

from libc.stdlib cimport malloc, free


cdef extern from "math.h":
    double atan2(double y, double x) nogil


from .spoke_sort import sort_spokes_at_wheel


DTYPE = np.int
ctypedef np.int_t DTYPE_t


@cython.boundscheck(False)
def remap_graph_element(np.ndarray[DTYPE_t, ndim=1] elements,
                        np.ndarray[DTYPE_t, ndim=1] old_to_new):
    """Remap elements in an array in place.

    Parameters
    ----------
    elements : ndarray of int
        Identifiers of elements.
    old_to_new : ndarray of int
        Mapping from the old identifier to the new identifier.
    """
    cdef int n_elements = elements.size
    cdef int i

    for i in range(n_elements):
      elements[i] = old_to_new[elements[i]]


@cython.boundscheck(False)
def reorder_patches(np.ndarray[DTYPE_t, ndim=1] links_at_patch,
                    np.ndarray[DTYPE_t, ndim=1] offset_to_patch,
                    np.ndarray[DTYPE_t, ndim=1] sorted_patches):
    cdef int i
    cdef int patch
    cdef int offset
    cdef int n_links
    cdef int n_patches = len(sorted_patches)
    cdef int *new_offset = <int *>malloc(len(offset_to_patch) * sizeof(int))
    cdef int *new_patches = <int *>malloc(len(links_at_patch) * sizeof(int))

    try:
        new_offset[0] = 0
        for patch in range(n_patches):
            offset = offset_to_patch[sorted_patches[patch]]
            n_links = offset_to_patch[sorted_patches[patch] + 1] - offset

            new_offset[patch + 1] = new_offset[patch] + n_links
            for i in range(n_links):
                new_patches[new_offset[patch] + i] = links_at_patch[offset + i]

        for i in range(len(links_at_patch)):
            links_at_patch[i] = new_patches[i]
        for i in range(len(offset_to_patch)):
            offset_to_patch[i] = new_offset[i]
    finally:
        free(new_offset)
        free(new_patches)


@cython.boundscheck(False)
def calc_center_of_patch(np.ndarray[DTYPE_t, ndim=1] links_at_patch,
                         np.ndarray[DTYPE_t, ndim=1] offset_to_patch,
                         np.ndarray[np.float_t, ndim=2] xy_at_link,
                         np.ndarray[np.float_t, ndim=2] xy_at_patch):
    cdef int patch
    cdef int link
    cdef int i
    cdef int offset
    cdef int n_links
    cdef int n_patches = len(xy_at_patch)
    cdef float x
    cdef float y

    for patch in range(n_patches):
        offset = offset_to_patch[patch]
        n_links = offset_to_patch[patch + 1] - offset
        x = 0.
        y = 0.
        for i in range(offset, offset + n_links):
            link = links_at_patch[i]
            x += xy_at_link[link, 0]
            y += xy_at_link[link, 1]
        xy_at_patch[patch, 0] = x / n_links
        xy_at_patch[patch, 1] = y / n_links


@cython.boundscheck(False)
def calc_midpoint_of_link(np.ndarray[DTYPE_t, ndim=2] nodes_at_link,
                          np.ndarray[np.float_t, ndim=1] x_of_node,
                          np.ndarray[np.float_t, ndim=1] y_of_node,
                          np.ndarray[np.float_t, ndim=2] xy_of_link):
    cdef int link
    cdef int n_links = nodes_at_link.shape[0]

    for link in n_links:
        link_tail = nodes_at_link[link][0]
        link_head = nodes_at_link[link][1]

        xy_of_link[link][0] = (x_of_node[link_tail] +
                               x_of_node[link_head]) * .5
        xy_of_link[link][1] = (y_of_node[link_tail] +
                               y_of_node[link_head]) * .5


@cython.boundscheck(False)
def reorder_links_at_patch(np.ndarray[DTYPE_t, ndim=1] links_at_patch,
                           np.ndarray[DTYPE_t, ndim=1] offset_to_patch,
                           np.ndarray[np.float_t, ndim=2] xy_of_link):
    cdef int n_patches = len(offset_to_patch) - 1

    xy_of_patch = np.empty((n_patches, 2), dtype=float)
    calc_center_of_patch(links_at_patch, offset_to_patch, xy_of_link,
                         xy_of_patch)
    sort_spokes_at_wheel(links_at_patch, offset_to_patch, xy_of_patch,
                         xy_of_link)


@cython.boundscheck(False)
def get_angle_of_link(np.ndarray[DTYPE_t, ndim=2] nodes_at_link,
                      np.ndarray[np.float_t, ndim=2] xy_of_node,
                      np.ndarray[np.float_t, ndim=1] angle_of_link):
    cdef int link
    cdef float link_tail_x
    cdef float link_tail_y
    cdef float link_head_x
    cdef float link_head_y
    cdef int n_links = nodes_at_link.shape[0]

    for link in range(n_links):
        link_tail_x = xy_of_node[nodes_at_link[link][0]][0]
        link_tail_y = xy_of_node[nodes_at_link[link][0]][1]
        link_head_x = xy_of_node[nodes_at_link[link][1]][0]
        link_head_y = xy_of_node[nodes_at_link[link][1]][1]

        angle_of_link[link] = atan2(link_head_y - link_tail_y,
                                    link_head_x - link_head_y)


@cython.boundscheck(False)
def reorient_links(np.ndarray[DTYPE_t, ndim=2] nodes_at_link,
                   np.ndarray[DTYPE_t, ndim=1] xy_of_node):
    """Reorient links to point up and to the right.

    Parameters
    ----------
    nodes_at_link : ndarray of int, shape `(n_nodes, 2)`
        Identifier for node at link tail and head.
    xy_of_node : ndarray of float, shape `(n_nodes, 2)`
        Coordinate of node as `(x, y)`.
    """
    cdef int link
    cdef int temp
    cdef double angle
    cdef int n_links = nodes_at_link.shape[0]
    cdef double minus_45 = - np.pi * .25
    cdef double plus_135 = np.pi * .75

    angle_of_link = np.empty(n_links, dtype=n_links)
    get_angle_of_link(nodes_at_link, xy_of_node, angle_of_link)

    for link in range(n_links):
        angle = angle_of_link[link]
        if angle < minus_45 or angle > plus_135:
            temp = nodes_at_link[link, 0]
            nodes_at_link[link, 0] = nodes_at_link[link, 1]
            nodes_at_link[link, 1] = temp
