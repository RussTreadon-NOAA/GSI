cmake_minimum_required(VERSION 3.20)

project(GSIApp
        VERSION 1.0.0
        LANGUAGES C Fortran)

set(CMAKE_DIRECTORY_LABELS ${PROJECT_NAME})

enable_testing()
include(GNUInstallDirs)

if(NOT CMAKE_BUILD_TYPE MATCHES "^(Debug|Release|RelWithDebInfo|MinSizeRel)$")
  message(STATUS "Setting build type to 'Release' as none was specified.")
  set(CMAKE_BUILD_TYPE
      "Release"
      CACHE STRING "Choose the type of build." FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Release" "MinSizeRel" "RelWithDebInfo")
endif()

if(NOT CMAKE_C_COMPILER_ID MATCHES "^(GNU|Intel|Clang|AppleClang)$")
  message(WARNING "${CMAKE_C_COMPILER_ID} is not supported.")
endif()

if(NOT CMAKE_Fortran_COMPILER_ID MATCHES "^(GNU|Intel)$")
  message(WARNING "${CMAKE_Fortran_COMPILER_ID} is not supported.")
endif()

# User options
option(OPENMP "Enable OpenMP Threading" OFF)
option(ENABLE_MKL "Use MKL for LAPACK implementation (if available)" ON)
option(BUILD_GSDCLOUD "Build GSD Cloud Analysis Library" OFF)
option(BUILD_MGBF "Build MGBF Library" ON)
option(BUILD_GSI "Build GSI" ON)
option(BUILD_ENKF "Build EnKF" ON)
option(BUILD_REG_TESTING "Build the Regression Testing Suite" OFF)

set(GSI_VALID_MODES "GFS" "Regional" "3DRTMA")
set(GSI_MODE "GFS" CACHE STRING "Choose the GSI Application.")
set_property(CACHE GSI_MODE PROPERTY STRINGS ${GSI_VALID_MODES})

# Ensure valid GSI_MODE is selected
if(NOT GSI_MODE IN_LIST GSI_VALID_MODES)
  message(FATAL_ERROR "GSI_MODE must be one of ${GSI_VALID_MODES}")
endif()

if(GSI_MODE MATCHES "3DRTMA")
  set(BUILD_GSDCLOUD "ON")
  set(USE_GSDCLOUD "ON")
endif()

# Echo user options
message(STATUS "OPENMP ................. ${OPENMP}")
message(STATUS "ENABLE_MKL ............. ${ENABLE_MKL}")
message(STATUS "BUILD_GSDCLOUD ......... ${BUILD_GSDCLOUD}")
message(STATUS "BUILD_MGBF ............. ${BUILD_MGBF}")
message(STATUS "BUILD_GSI .............. ${BUILD_GSI}")
message(STATUS "BUILD_ENKF ............. ${BUILD_ENKF}")
message(STATUS "BUILD_REG_TESTING ...... ${BUILD_REG_TESTING}")

# Build components
add_subdirectory(src)

# Download and copy binary fix files if submodule has been cloned
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/fix/CMakeLists.txt)
  add_subdirectory(fix)
endif()

if(BUILD_REG_TESTING)
  add_subdirectory(regression)
endif()

#add_subdirectory(unit-tests)
