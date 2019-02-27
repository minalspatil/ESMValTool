;;#############################################################################
;; mjo_precip_u850-200_propagation.ncl
;; Author: Shiyu Wang (SMHI, Sweden)
;;         (though adapted from an NCAR script of the US CLIVAR MJO WG)
;; Contributor: Martin Evaldssson (SMHI, Sweden), some ESMValTool adapations
;; EMBRACE project
;;#############################################################################
;; Description
;;     The MJO diagnostics are developed by the US CLIVAR MJO Working Group. The
;;     majority of scripts are based on example scripts
;;     at http://ncl.ucar.edu/Applications/mjoclivar.shtml.
;;
;; Required diag_script_info attributes (diagnostics specific)
;;     nameSeason: Name of season
;;
;; Required variable_info attributes (variable specific)
;;    long_name:                    Name to store in derived varible
;;    units:                        Units for derived variable
;;    map_ref_Levels:
;;    map_diff_Levels:
;;
;; Caveats
;;
;; Reference: Adapted from the MJO Clivar scripts available at
;;            http://ncl.ucar.edu/Applications/mjoclivar.shtml
;;
;; Modification history
;;     20170918-A_bock_ls: added tags for reporting
;;     20151027-A_laue_ax: moved call to 'write_references' to the beginning
;;                         of the code
;;     20150828-A_wang_sh: written
;;
;; ############################################################################

load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_code.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_csm.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/contributed.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/diagnostics_cam.ncl"

;; Temporary file updated by Python on the fly
load "./interface_data/ncl.interface"

load "./interface_scripts/auxiliary.ncl"
load "./interface_scripts/data_handling.ncl"
load "./interface_scripts/messaging.ncl"

load "./diag_scripts/lib/ncl/set_operators.ncl"
load "./diag_scripts/lib/ncl/statistics.ncl"
load "./diag_scripts/aux/SAMonsoon/SAMonsoon.ncl"
load "./diag_scripts/aux/SAMonsoon/descriptions.ncl"

load "./diag_scripts/aux/mjo/mjo.ncl"
load "./plot_scripts/ncl/mjo_level1.ncl"
load "./plot_scripts/ncl/mjo_level2.ncl"

load "./diag_scripts/lib/ncl/meta_data.ncl"

;*********************************************************************

begin
    ;; ============================================
    ;; ||                                        ||
    ;; ||         READING CONFIGURATION          ||
    ;; ||                                        ||
    ;; ============================================

    verbosity = stringtointeger(getenv("ESMValTool_verbosity"))
    ;; 'diag_script' if fetched from ncl.interface
    info_output("<<<<<<<< Entering " + diag_script, verbosity, 4)
    info_output("+++++++++++++++++++++++++++++++++++++++++++++++++", verbosity, 1)
    info_output("plot - " + diag_script + " (var: " + variables(0) + ")", verbosity, 1)
    info_output("+++++++++++++++++++++++++++++++++++++++++++++++++", verbosity, 1)
    diag_script_base = basename(diag_script)

    dim_MOD = dimsizes(models@name)
    dim_VAR = dimsizes(variables)
    var0 = variables(0)
    field_type0 = field_types(0)

    ;; ============================================
    ;; ||                                        ||
    ;; ||          REFERENCES INFO               ||
    ;; ||                                        ||
    ;; ============================================
    write_references(diag_script,       \  ; script name
                     "A_wang_sh",       \  ; authors
                     "",                \  ; contributors
                     "",                \  ; diag_references
                     "",                \  ; obs_references
                     "P_embrace")          ; proj_acknowledgements
end

; Load variable_info
begin
    vardeffile = "interface_data/" + var0 + "_info.tmp"
    loadscript(vardeffile)
end

begin

    ;; 'show_debuginfo' if fetched from ncl.interface
    if (.not. isdefined("show_debuginfo")) then
        debuginfo = False
    else
        debuginfo = show_debuginfo
    end if

    ;; Check valid plot fields
    valid_plot_field = (/"T2Ds"/)
    ind_f = inlist(field_type0, valid_plot_field)
    if (any(ind_f .eq. False)) then
        print("fatal:can't use field, " + field_type0 + " for this diag_script")
        status_exit(1)
    end if
    delete(valid_plot_field)
    delete(ind_f)

    ;; -------------------------------------------------
    ;; Check that required 'diag_script_info'-attributes
    ;; (from the SAMonsoon cfg-file) are present
    ;; -------------------------------------------------
    required_attributes = (/"nameSeason"/)
    exit_if_missing_atts(diag_script_info, required_attributes)

    ;; Abbreviate a little...
    di = diag_script_info

    ;; ============================================
    ;; ||                                        ||
    ;; ||         COMPUTING DIAGNOSTICS          ||
    ;; ||                                        ||
    ;; ============================================

    ;; ---------------------------------------------
    ;; Data structure for storing the models defined
    ;; in the namelist
    ;; ---------------------------------------------
    nml_data_vault = True

    do idx_mod = 0, dim_MOD - 1
        nml_data_vault = read_data(idx_mod, var0, field_type0)
    end do

   ;; Reference model index
    idx_ref = get_ref_model_idx(models, var_attr_ref(0))

    ;; ============================================
    ;; ||                                        ||
    ;; ||          PLOTTING DIAGNOSTICS          ||
    ;; ||                                        ||
    ;; ============================================

    seasons = di@nameSeason

    ;; Output dir
    ;; 'plot_dir' is fetched from ncl.interface
    diag_script_base = basename(diag_script)
    output_dir = get_output_dir(plot_dir, diag_script_base)

    optPlot = True

    ;-----------------------------------------------------------------------------
    ; for meta data
        climofiles = new(dim_MOD, string)
        do ii = 0, dim_MOD - 1
            climofiles(ii) = \
                interface_get_inpaths(ii) + "/" \
                + interface_get_infile(variables(0), field_types(0), ii)
        end do
        domain = "DM_global"
        alltags = array_append_record(tags, (/"PT_other", "ST_spectrum", domain/), 0)
        contrib_authors = (/"A_wang_sh"/)
    ;-----------------------------------------------------------------------------


    do s = 0, dimsizes(seasons) - 1

        ;; ***************************************************************
        ;; ------------------ Open files for plots -----------------------
        aux_title_info = seasons(s)
        output_filename = interface_get_figure_filename(diag_script_base,\
                                                        var0,\
                                                        field_type0,\
                                                        aux_title_info,\
                                                        -1)
        wks = gsn_open_wks(output_file_type, output_dir + output_filename)

        plot = new(dim_MOD, "graphic")
        dummy = new((/dim_MOD, 4/), "graphic")
        gsn_define_colormap(wks, "prcp_2")

        do idx_mod = 0, dim_MOD - 1
            ;; check the reference data and read in
            if (idx_mod .eq. idx_ref) then
                idx_mod_pr = idx_ref
            end if
        end do

        Ref_Read = True
        wfo = calc_wave_freq(nml_data_vault,\
                             di,\
                             idx_mod_pr,\
                             seasons(s),\
                             Ref_Read)

        optPlot@gsnLeftString = models@name(idx_mod_pr)
        plot(0) = mjo_wave_freq_plot(wks,\
                                     wfo(:, :),\
                                     dummy,\
                                     idx_mod_pr,\
                                     optPlot,\
                                     di)
        delete(wfo)

        plot_n = 1
        do idx_mod = 0, dim_MOD - 1
            ;; read in non-reference data
            if (idx_mod .ne. idx_ref) then

                Ref_Read = False
                wfo = calc_wave_freq(nml_data_vault,\
                                     di,\
                                     idx_mod,\
                                     seasons(s),\
                                     Ref_Read)

                optPlot@gsnLeftString = models@name(idx_mod)
                plot(plot_n) = mjo_wave_freq_plot(wks,\
                                                  wfo(:, :),\
                                                  dummy,\
                                                  idx_mod,\
                                                  optPlot,\
                                                  di)
                plot_n = plot_n + 1
                delete(wfo)
            end if
        end do

        ;; common resources for panel plots
        pan = True
        pan@gsnMaximize = True
        pan@gsnPaperOrientation = "portrait"
        pan@txString =seasons(s)
        pan@gsnPanelLabelBar = True

        n_p = dimsizes(plot) / 2
        if (mod(dimsizes(plot), 2) .ne. 0) then
            n_p = n_p + 1
        end if
        gsn_panel(wks, plot, (/n_p, 2/), pan)    ; panel plot

        delete(plot)
        delete(pan)
        delete(n_p)

        ; add meta data to plot (for reporting)
        caption = "Madden Julian Oscillation Climate Variability: " + \
                  "wavenumber - frequency spectra of season " + seasons(s) + \
                  " of variable " + var0

        id = diag_script + "_" + variables(0) + "_" + seasons(s)

        outfile = output_dir + output_filename + "." + output_file_type

        ESMValMD(outfile, alltags, caption, id, var0, models@name, climofiles, diag_script, contrib_authors)

    end do  ; end number of season loop

    info_output(">>>>>>>> Leaving " + diag_script, verbosity, 4)
end