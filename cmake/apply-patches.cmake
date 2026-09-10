# Apply one or more unified patches without failing when a patch is already
# present in an incremental ExternalProject build.
if( NOT DEFINED GEOS_PATCH_FILES OR GEOS_PATCH_FILES STREQUAL "" )
  message( FATAL_ERROR "GEOS_PATCH_FILES must name at least one patch file." )
endif()

if( NOT DEFINED GEOS_PATCH_STRIP OR GEOS_PATCH_STRIP STREQUAL "" )
  set( GEOS_PATCH_STRIP 1 )
endif()

# A pipe is used as the list separator because semicolons are list separators
# in CMake command-line definitions.
string( REPLACE "|" ";" _geos_patch_files "${GEOS_PATCH_FILES}" )

foreach( _geos_patch_file IN LISTS _geos_patch_files )
  if( NOT EXISTS "${_geos_patch_file}" )
    message( FATAL_ERROR "Patch file does not exist: ${_geos_patch_file}" )
  endif()

  execute_process(
    COMMAND patch --batch --forward --dry-run -p${GEOS_PATCH_STRIP} -i "${_geos_patch_file}"
    RESULT_VARIABLE _geos_patch_forward_status
    OUTPUT_VARIABLE _geos_patch_forward_output
    ERROR_VARIABLE _geos_patch_forward_error )

  if( _geos_patch_forward_status EQUAL 0 )
    execute_process(
      COMMAND patch --batch --forward -p${GEOS_PATCH_STRIP} -i "${_geos_patch_file}"
      RESULT_VARIABLE _geos_patch_apply_status
      OUTPUT_VARIABLE _geos_patch_apply_output
      ERROR_VARIABLE _geos_patch_apply_error )
    if( NOT _geos_patch_apply_status EQUAL 0 )
      message( FATAL_ERROR
        "Failed to apply patch ${_geos_patch_file}:\n"
        "${_geos_patch_apply_output}${_geos_patch_apply_error}" )
    endif()
  else()
    execute_process(
      COMMAND patch --batch --reverse --dry-run -p${GEOS_PATCH_STRIP} -i "${_geos_patch_file}"
      RESULT_VARIABLE _geos_patch_reverse_status
      OUTPUT_VARIABLE _geos_patch_reverse_output
      ERROR_VARIABLE _geos_patch_reverse_error )
    if( _geos_patch_reverse_status EQUAL 0 )
      message( STATUS "Patch already applied: ${_geos_patch_file}" )
    else()
      message( FATAL_ERROR
        "Patch cannot be applied or recognized as already applied: ${_geos_patch_file}\n"
        "Forward check:\n${_geos_patch_forward_output}${_geos_patch_forward_error}\n"
        "Reverse check:\n${_geos_patch_reverse_output}${_geos_patch_reverse_error}" )
    endif()
  endif()
endforeach()
