IF(NOT DAS_BISON_INCLUDED)
    SET(DAS_BISON_INCLUDED TRUE)
    MESSAGE(STATUS "dasBison module included.")

    ADD_MODULE_DAS_FROM_DESCRIPTOR(bison bison)

    set_property(GLOBAL APPEND PROPERTY DAS_ARCH_EXTRACT_SPECS
        "modules/dasBison/bison|modules/dasBison|${DAS_INSTALL_MODULESDIR}/dasBison")

    install(DIRECTORY ${PROJECT_SOURCE_DIR}/modules/dasBison/bison
        DESTINATION ${DAS_INSTALL_MODULESDIR}/dasBison
        FILES_MATCHING
        PATTERN "*.das"
    )
    install(FILES ${PROJECT_SOURCE_DIR}/modules/dasBison/.das_module
        DESTINATION ${DAS_INSTALL_MODULESDIR}/dasBison
    )

    das_lane_dastest_target(run_tests_dasbison COMMENT "Testing dasBison"
        FILES
            modules/dasBison/tests/lr_parse_tests.das
            modules/dasBison/tests/prec_tests.das
            modules/dasBison/tests/bison_macro_tests.das
            modules/dasBison/tests/bison_reader_tests.das
            modules/dasBison/tests/c11_tests.das
        JIT_FILES
            modules/dasBison/tests/bison_macro_tests.das
            modules/dasBison/tests/c11_tests.das
    )

    ADD_EXAMPLE_RUN(tutorials/dasBison/01_calculator.das)
    ADD_EXAMPLE_RUN(tutorials/dasBison/02_bison_reader.das)

ENDIF()
