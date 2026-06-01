help([[
]])

prepend_path("MODULEPATH", "/ncrc/proj/epic/spack-stack/c6/spack-stack-2.1.0/envs/ue-oneapi-2025.2.1/modules/Core")

local python_ver=os.getenv("python_ver") or "3.11"
local stack_intel_ver=os.getenv("stack_intel_ver") or "2025.2.1"
local stack_cray_mpich_ver=os.getenv("stack_cray_mpich_ver") or "8.1.32"
local cmake_ver=os.getenv("cmake_ver") or "3.31.8"
local crtm_fix_ver=os.getenv("crtm_fix_ver") or "3.1.2.0"

load(pathJoin("stack-intel-oneapi-compilers", stack_intel_ver))
load(pathJoin("stack-cray-mpich", stack_cray_mpich_ver))
load(pathJoin("python", python_ver))
load(pathJoin("cmake", cmake_ver))

local netcdf_c_ver=os.getenv("netcdf_c_ver") or "4.9.2"
local netcdf_fortran_ver=os.getenv("netcdf_fortran_ver") or "4.6.1"

local bufr_ver=os.getenv("bufr_ver") or "12.1.0"
local bacio_ver=os.getenv("bacio_ver") or "2.6.0"
local w3emc_ver=os.getenv("w3emc_ver") or "2.13.0"
local ip_ver=os.getenv("ip_ver") or "5.4.0"
local sigio_ver=os.getenv("sigio_ver") or "2.3.3"
local sfcio_ver=os.getenv("sfcio_ver") or "1.4.2"
local nemsio_ver=os.getenv("nemsio_ver") or "2.5.5"
local wrf_io_ver=os.getenv("wrf_io_ver") or "1.3.0"
local ncio_ver=os.getenv("ncio_ver") or "1.1.2"
local crtm_ver=os.getenv("crtm_ver") or "3.1.3"
local ncdiag_ver=os.getenv("ncdiag_ver") or "1.1.2"
local prod_util_ver=os.getenv("prod_util_ver") or "2.1.2"

load(pathJoin("netcdf-c", netcdf_c_ver))
load(pathJoin("netcdf-fortran", netcdf_fortran_ver))

load(pathJoin("bufr", bufr_ver))
load(pathJoin("bacio", bacio_ver))
load(pathJoin("w3emc", w3emc_ver))
load(pathJoin("ip", ip_ver))
load(pathJoin("sigio", sigio_ver))
load(pathJoin("sfcio", sfcio_ver))
load(pathJoin("nemsio", nemsio_ver))
load(pathJoin("wrf-io", wrf_io_ver))
load(pathJoin("ncio", ncio_ver))
load(pathJoin("crtm", crtm_ver))
load(pathJoin("gsi-ncdiag", ncdiag_ver))
load(pathJoin("prod_util", prod_util_ver))


pushenv("GSI_BINARY_SOURCE_DIR", "/gpfs/f6/drsa-precip3/world-shared/role.glopara/fix/gsi/20251105")
setenv("CRTM_FIX", "/gpfs/f6/drsa-precip3/world-shared/role.glopara/fix/crtm/fix_LittleEndian")


setenv("CC","cc")
setenv("FC","ftn")
setenv("CXX","CC")
pushenv("CRAYPE_LINK_TYPE","dynamic")

unload("cray-libsci")
whatis("Description: GSI environment on GaeaC6 with Intel Compilers")
