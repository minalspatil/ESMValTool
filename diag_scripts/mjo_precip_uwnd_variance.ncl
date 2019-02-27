;*********************************************************************
; SAMonsoon_precip_propagation.ncl
;*********************************************************************
; NCL script
; SAMonsoon_precip_propagation.ncl, January 2013
; Martin.Evalsson@smhi.se
;*********************************************************************
; PIs: Klaus Wyser (SMHI) and Veronika Eyring (DLR)
; Lagged correlation of precipitation anomalies with respect to area
; avearged region in Indian Ocean
;
; Reference: Adapted from the MJO Clivar scripts available at,
;
; https://www.ncl.ucar.edu/Applications/Scripts/mjoclivar_8.ncl
; and
; https://www.ncl.ucar.edu/Applications/Scripts/mjoclivar_9.ncl
; http://ncl.ucar.edu/Applications/mjoclivar.shtml
;;
;; Modification history
;;     20170918-A_bock_ls: added tags for reporting
;;     20151027-A_laue_ax: moved call to 'write_references' to the beginning
;;                         of the code
;*********************************************************************
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

load "./plot_scripts/ncl/mjo_level1.ncl"
load "./plot_scripts/ncl/mjo_level2.ncl"
load "./diag_scripts/aux/mjo/mjo.ncl"

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
    var1 = variables(1)
    field_type0 = field_types(0)
    field_type1 = field_types(1)

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
    required_attributes = (/"nameVariSeason",\
                            "ihp",\
                            "nWgt",\
                            "sigma",\
                            "fca",\
                            "fcb",\
                            "cnLevels_pr_vari",\
                            "latrange_seasonal",\
                            "lonrange_seasonal"/)
    exit_if_missing_atts(diag_script_info, required_attributes)

    ;; Abbreviate a little...
    di = diag_script_info
    di@is_cyclic = False  ; Used when/if filling missing values with poisson

    ;; ============================================
    ;; ||                                        ||
    ;; ||         COMPUTING DIAGNOSTICS          ||
    ;; ||                                        ||
    ;; ============================================

    ;; Reference model index
    idx_ref_pr = get_ref_model_idx(models, var_attr_ref(0))
    idx_ref_ua = get_ref_model_idx(models, var_attr_ref(1))

    ;; -----------------------------------------------
    ;; Reset min_idx/max_idx
    ;; -----------------------------------------------
    min_idx = min((/idx_ref_pr, idx_ref_ua/))
    max_idx = max((/idx_ref_pr, idx_ref_ua/))

    ;; ---------------------------------------------
    ;; Data structure for storing the models defined
    ;; in the namelist
    ;; ---------------------------------------------

    nml_data_vault_pr = True
    nml_data_vault_ua = True

    do idx_mod = 0, dim_MOD - 1
       ;; Skip models<->parameter combinations that are explicitly
        ;; excluded in the xml-file
        curr_var_idx = ind(var0 .eq. variables)
        if (var_attr_exclude(curr_var_idx) .ne. model_attr_id(idx_mod)) then
            nml_data_vault_pr = read_data(idx_mod, var0, field_type0)
        end if
        curr_var_idx = ind(var1 .eq. variables)
        if (var_attr_exclude(curr_var_idx) .ne. model_attr_id(idx_mod)) then
            nml_data_vault_ua = read_data(idx_mod, var1, field_type1)
        end if
    end do

    seasons = di@nameVariSeason
    ;; Output dir
    ;; 'plot_dir' is fetched from ncl.interface
    diag_script_base = basename(diag_script)
    output_dir = get_output_dir(plot_dir, diag_script_base)

    optPlot = True
    optPlot@gsnRightString = "U(m^2/s^2): Line"

    ;-----------------------------------------------------------------------------
    ; for meta data
        climofiles = new(dim_MOD, string)
        do ii = 0, dim_MOD - 1
            climofiles(ii) = \
                interface_get_inpaths(ii) + "/" \
                + interface_get_infile(variables(0), field_types(0), ii)
        end do
        domain = "DM_reg"
        alltags = array_append_record(tags, (/"PT_geo", "ST_var", domain/), 0)
        contrib_authors = (/"A_wang_sh"/)
    ;-----------------------------------------------------------------------------

    ;; %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    ;;loop through seasons
    do s = 0, dimsizes(seasons) - 1
        ;; ***************************************************************
        ;; ------------------ Open files for plots -----------------------
        aux_title_info = seasons(s)
        output_filename = interface_get_figure_filename(diag_script_base,\
                                                        var0 + var1,\
                                                        field_type0,\
                                                        aux_title_info,\
                                                        -1)
        wks = gsn_open_wks(output_file_type, output_dir + output_filename)

        plot = new(dim_MOD, "graphic")
        gsn_define_colormap(wks, "amwg")

        do idx_mod = 0, dim_MOD - 1
            ;;------------------------
            ;; Extract and process data
            ;;------------------------
            ;; Check for reference data sets and plot reference
            if (any(idx_mod .eq. (/idx_ref_pr, idx_ref_ua/))) then

                ;; Check if there's a single reference data set
                if (idx_ref_pr .eq. idx_ref_ua) then

                    idx_mod_pr = idx_mod
                    idx_mod_ua = idx_mod

                ;; If there are two separate data sets, only use them once
                ;; Skip the second time (max_idx)
                else if (idx_mod .eq. max_idx) then
                    continue
                else  ; Use them the first time (min_idx)

                    idx_mod_pr = idx_ref_pr
                    idx_mod_ua = idx_ref_ua

                end if
                end if
            end if
        end do

        cal_vari = calc_pr_ua_vari(nml_data_vault_pr,\
                                   nml_data_vault_ua,\
                                   di,\
                                   idx_mod_pr,\
                                   idx_mod_ua,\
                                   seasons(s))

        pr_vari = cal_vari[0]
        ua_vari = cal_vari[1]
        optPlot@gsnLeftString = models@name(idx_mod_pr) + "  precip (mm^2/day^2): color"
        plot(0) = mjo_pr_ua_vari_plot(wks,\
                                      pr_vari,\
                                      ua_vari,\
                                      optPlot,\
                                      di)

        delete(cal_vari)
        delete(pr_vari)
        delete(ua_vari)
        delete(idx_mod_pr)
        delete(idx_mod_ua)

        plot_n = 1

        do idx_mod = 0, dim_MOD - 1
            ;;------------------------
            ;; Extract and process non-reference data
            ;;------------------------
            ;; Check for reference data sets and plot reference
            if (any(idx_mod .eq. (/idx_ref_pr, idx_ref_ua/))) then
                continue
            else  ; non reference dataset
                idx_mod_pr = idx_mod
                idx_mod_ua = idx_mod

                cal_vari = calc_pr_ua_vari(nml_data_vault_pr,\
                                           nml_data_vault_ua,\
                                           di,\
                                           idx_mod_pr,\
                                           idx_mod_ua,\
                                           seasons(s))

                pr_vari = cal_vari[0]
                ua_vari = cal_vari[1]
                optPlot@gsnLeftString = models@name(idx_mod_pr)\
                                      + "   precip (mm^2/day^2): color"
                plot(plot_n) = mjo_pr_ua_vari_plot(wks,\
                                                   pr_vari,\
                                                   ua_vari,\
                                                   optPlot,\
                                                   di)

                plot_n = plot_n + 1

                delete(cal_vari)
                delete(pr_vari)
                delete(ua_vari)
                delete(idx_mod_pr)
                delete(idx_mod_ua)
            end if
        end do  ; idx_mod loop
        ;; Common resources for panel plots
        pan = True
        pan@gsnMaximize = True
        pan@gsnPaperOrientation = "portrait"
        pan@txString = seasons(s)
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
                  "variance in season " + seasons(s) + \
                  " of variable " + var0 + " and " + var1

        id = diag_script + "_" + variables(0) + "_" + seasons(s)

        outfile = output_dir + output_filename + "." + output_file_type

        ESMValMD(outfile, alltags, caption, id, var0, models@name, climofiles, diag_script, contrib_authors)

    end do  ; End seasons

    info_output(">>>>>>>> Leaving " + diag_script, verbosity, 4)
end