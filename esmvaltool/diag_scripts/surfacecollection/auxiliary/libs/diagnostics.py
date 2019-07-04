#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Fri Jun 21 13:05:25 2019

@author: bmueller
"""
import iris
import logging
import os
from .utilities import set_metadata, checked_ref, correlation, corr_extract
import numpy as np
import pandas as pd

logger = logging.getLogger(os.path.basename(__file__))

def glob_temp_mean(data, **kwargs):
    """
    produces global temporal mean
    -----------------------------
    returns a list of mean cubes
    """
    cubes = []
    
    for cube in data.get_all():
        cubes.append(cube.collapsed("time", iris.analysis.MEAN))
    
    return cubes


def glob_temp_mean_absdiff(data, **kwargs):
    """
    produces global temporal mean absolute differences
    --------------------------------------------------
    returns a list of difference cubes
    """
    cubes = []
    
    if len(data.get_ref()) != 1:
        logger.error("There needs to be one and only one reference dataset")
    ref = glob_temp_mean(data.ref_only())
    ref = checked_ref(ref, num=1)
    nonref = glob_temp_mean(data.nonref_only())

    for cube in nonref:
        diff = cube - ref
        diff.metadata = set_metadata(cube, ref,
                                     "global_temp_mean_absdiff")
        cubes.append(diff)
    
    return cubes


def glob_temp_mean_reldiff(data, **kwargs):
    """
    produces global temporal mean relative differences
    --------------------------------------------------
    returns a list of mean cubes
    """
    cubes = []
    
    ref = glob_temp_mean(data.ref_only())
    ref = checked_ref(ref, num=1)

    for cube in glob_temp_mean_absdiff(data):
        reldiff = cube / ref
        reldiff.metadata = set_metadata(cube, ref,
                                        "global_temp_mean_reldiff")
        cubes.append(reldiff)
    
    return cubes


def percentiles(data, **kwargs):
    """
    produces pixelwise temporal percentiles
    ---------------------------------------
    returns a dict of percentile cubes
    """
    
    if "percentiles" not in kwargs.keys():
        logger.error("option percentiles required for this diagnostic")
    else:
        percentiles = kwargs["percentiles"]
        if len(percentiles) == 0:
            percentiles = [0.5]
            logger.warning("no percentiles given (None), " +
                           "median (0.5) produced instead")
    
    if len(data.get_ref()) != 1:
        logger.error("There needs to be one and only one reference dataset")
    ref = checked_ref(data.get_ref(), num=1)
    
    nonref = data.get_nonref()
    
    refperc = ref.collapsed("time", iris.analysis.PERCENTILE,
                            percent=[p*100 for p in percentiles])
    
    nonrefperc = []
    
    for cube in nonref:
        nonrefperc.append(cube.collapsed("time", iris.analysis.PERCENTILE,
                                         percent=[p*100 for p in percentiles]))
        
    res_list = []
    
    for p in percentiles:
        
        perc_check = lambda perc: perc==p*100
        perc_constraint = iris.Constraint(percentile_over_time=perc_check)
        
        refp = refperc.extract(perc_constraint)
        nonrefp = [nrp.extract(perc_constraint) for nrp in nonrefperc]
        
        corrs = [correlation(refp, nrp) for nrp in nonrefp]
        
        res_list.append({str(p):{"ref":refp,
                                 "nonref":nonrefp,
                                 "corr":corrs}})
    
    corr_data = corr_extract(res_list)
    
    corr_df = pd.DataFrame(data=corr_data,
                columns=[dset.metadata.attributes["source_file"].split(
                        os.sep)[-1] for dset in data.get_all()],
                index=percentiles)
    
    res_list.append(corr_df)
    
    return res_list