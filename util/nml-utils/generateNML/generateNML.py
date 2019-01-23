"""
Call like:
python util/nml-utils/generateNML/generateNML.py --project PROJECT --name NAME --product PRODUCT --institute INSTITUTE --model MODEL --experiment EXPERIMENT --mip MIP --ensemble ENSEMBLE --grid GRID --start_year START_YEAR --end_year END_YEAR --variable VARIABLE

"""
import os
from jinja2 import Template
import argparse
import xmltodict

t_nml = """
<namelist>
<include href="./config_private.xml" />
<namelist_summary>
###############################################################################
namelist_cmip6_routine_evaluation.xml

Description
Autogenerated namelist for routine evaluation of CMIP6 data

Author
Core Team

Project
CMIP6-DICAD

Reference

This namelist is part of the ESMValTool
###############################################################################
</namelist_summary>

<GLOBAL>
    <write_plots type="boolean">           True         </write_plots>
    <write_netcdf type="boolean">          True         </write_netcdf>
    <force_processing type="boolean">     False         </force_processing>
    <wrk_dir type="path">                  @{WORKPATH}  </wrk_dir>
    <plot_dir type="path">                 @{PLOTPATH}/ </plot_dir>
    <climo_dir type="path">                @{CLIMOPATH} </climo_dir>
    <write_plot_vars type="boolean">       True         </write_plot_vars>
    <max_data_filesize type="integer">      100         </max_data_filesize>
    <max_data_blocksize type="integer">     500         </max_data_blocksize>
    <verbosity type="integer">               1          </verbosity>
    <exit_on_warning type="boolean">      True          </exit_on_warning>
    <output_file_type>                      png         </output_file_type>
    <tags>                                P_cmip6       </tags>
</GLOBAL>

<MODELS>
    <model>{{ m }} </model>
</MODELS>


<DIAGNOSTICS>
    <diag>
        <description>         Tutorial diagnostic  </description>
        <variable_def_dir>    ./variable_defs/     </variable_def_dir>
        <variable>            {{ v }}                </variable>
        <field_type>          {{ ft }}                  </field_type>
        <diag_script_cfg_dir> ./nml/cfg_MyDiag/    </diag_script_cfg_dir>
        <tags>                R_atmos, T_atmDyn, T_phys </tags>

        <diag_script cfg="cfg_MyDiag.ncl"> MyDiag.ncl  </diag_script>
    </diag>
</DIAGNOSTICS>

<ESGF>
    <config_file>./esgf_config.xml</config_file>
</ESGF>

</namelist>
"""
t_mline =" ".join([
   '{{ project }}',
   '{{ name }}',
   '{{ product }}',
   '{{ institute }}',
   '{{ model }}',
   '{{ experiment }}',
   '{{ time_freq }}',
   '{{ realm }}',
   '{{ mip }}',
   '{{ ensemble }}',
   '{{ version }}',
   '{{ grid }}',
   '{{ start_year }}',
   '{{ end_year }}',
   '{{ ptid }}'])


def get_modelline(**kwargs):
    d = dict()
    d['Amon'] = {'time_freq':'mon', 'realm':'atmos'}
    d['Omon'] = {'time_freq':'mon', 'realm':'ocean'}
    d['Lmon'] = {'time_freq':'mon', 'realm':'land'}

    kwargs.update({'version': 'latest', 'ptid':'CMIP6_template'})
    if 'mip' in kwargs.keys():
        if kwargs['mip'] in d.keys():
            kwargs.update(d[kwargs['mip']])
    tt_mline = Template(t_mline)
    return tt_mline.render(**kwargs)

def get_namelist(**kwargs):
    d = dict()
    d['tas'] = {'ft':'T2Ms'}
    d['ta'] =  {'ft':'T3M'}
    d['uas'] =  {'ft':'T2Ms'}
    d['prw'] =  {'ft':'T2M'}

    tt_nml = Template(t_nml)
    if 'variable' in kwargs.keys():
        if kwargs['variable'] in d.keys():
            kwargs.update(d[kwargs['variable']])
            return tt_nml.render(m=get_modelline(**kwargs), v=kwargs['variable'], ft=kwargs['ft'])
    return tt_nml.render(m=get_modelline(**kwargs), v=None, ft=None)

def get_template_string(namelist):
    """Return a template string for a given namelist."""

    if not os.path.isfile(namelist):
        raise Exception

    with open(namelist, 'r') as f:
        j = xmltodict.parse(f.read())

    if j['namelist']['MODELS'] is not None:
        j['namelist']['MODELS'] = ["{{ global_modelline }}"]

    number_of_diagblocks = len(j['namelist']['DIAGNOSTICS']['diag'])
    for i in range(number_of_diagblocks):
        j['namelist']['DIAGNOSTICS']['diag'][i]['model'] = ["{{ diag_modelline }}"]

    return xmltodict.unparse(j, pretty=True)

def main():
    parser = argparse.ArgumentParser(description='Generate routine evaluation namelist.')
    parser.add_argument('--project', dest='project')
    parser.add_argument('--name', dest='name')
    parser.add_argument('--product', dest='product')
    parser.add_argument('--institute', dest='institute')
    parser.add_argument('--model', dest='model')
    parser.add_argument('--experiment', dest='experiment')
    parser.add_argument('--mip', dest='mip')
    parser.add_argument('--ensemble', dest='ensemble')
    parser.add_argument('--grid', dest='grid')
    parser.add_argument('--start_year', dest='start_year')
    parser.add_argument('--end_year', dest='end_year')
    parser.add_argument('--variable', dest='variable')
    parser.add_argument('--namelist', dest='namelist')

    args = parser.parse_args()

    kwa = dict(args._get_kwargs())

    #print(get_namelist(**kwa))
    namelist = kwa['namelist']
    print(get_template_string(namelist))

if __name__ == "__main__":
    main()