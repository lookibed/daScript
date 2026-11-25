IF(NOT DAS_FLEX_INCLUDED)
    SET(DAS_FLEX_INCLUDED TRUE)
    MESSAGE(STATUS "dasFlex module included.")

    ADD_MODULE_DAS_FROM_DESCRIPTOR(flex flex)

    install(DIRECTORY ${PROJECT_SOURCE_DIR}/modules/dasFlex/flex
        DESTINATION ${DAS_INSTALL_MODULESDIR}/dasFlex
        FILES_MATCHING
        PATTERN "*.das"
    )
    install(FILES ${PROJECT_SOURCE_DIR}/modules/dasFlex/.das_module
        DESTINATION ${DAS_INSTALL_MODULESDIR}/dasFlex
    )

    das_lane_dastest_target(run_tests_dasflex COMMENT "Testing dasFlex"
        FILES
            modules/dasFlex/tests/flex_tests.das
            modules/dasFlex/tests/flex_reader_tests.das
        JIT_FILES
            modules/dasFlex/tests/flex_tests.das
    )

    ADD_EXAMPLE_RUN(tutorials/dasFlex/01_json_tokens.das)
    ADD_EXAMPLE_RUN(tutorials/dasFlex/02_flex_reader.das)
    ADD_EXAMPLE_RUN(tutorials/dasFlex/03_groups.das)

ENDIF()
