cmake_minimum_required(VERSION 3.22)
project(occt_qt_viewer_min LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# find Qt6 Widgets
# find_package(Qt6 REQUIRED COMPONENTS Widgets)
find_package(Qt6 COMPONENTS Widgets OpenGLWidgets REQUIRED)

# OpenCascade (Homebrew provides Config package in .../lib/cmake/opencascade)
find_package(OpenCASCADE REQUIRED)

# add_executable(occt_qt_viewer_min main.mm)
# add_executable(occt_qt_viewer_min occt_qt_viewer_min.mm)
add_executable(occt_qt_viewer_min occt_qt_viewer_min.cpp)
# add_executable(occt_qt_viewer_min winocct_qt_viewer_min.cpp)

# OCCT headers
target_include_directories(occt_qt_viewer_min PRIVATE ${OpenCASCADE_INCLUDE_DIR})

# Link Qt + OCCT
target_link_libraries(occt_qt_viewer_min PRIVATE
  Qt6::Widgets
  Qt6::OpenGLWidgets
  ${OpenCASCADE_LIBRARIES}
)

# macOS app bundle (optional, but nice)
set_target_properties(occt_qt_viewer_min PROPERTIES
  MACOSX_BUNDLE TRUE
)
