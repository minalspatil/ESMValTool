# pylint: disable=invalid-name, no-self-use, too-few-public-methods
"""Fixes for GFDL CM2p1 model."""
from ..fix import Fix
from ..CMIP5.GFDL_ESM2G import allvars as base_allvars


class allvars(base_allvars):
    pass


class sftof(Fix):
    """Fixes for sftof."""

    def fix_data(self, cube):
        """
        Fix data.

        Fixes discrepancy between declared units and real units

        Parameters
        ----------
        cube: iris.cube.Cube

        Returns
        -------
        iris.cube.Cube

        """
        metadata = cube.metadata
        cube *= 100
        cube.metadata = metadata
        return cube
