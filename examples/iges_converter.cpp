
#include <gismo.h>

#include "gsOpenCascade/gsReadOcct.h"
#include "gsOpenCascade/gsWriteOcct.h"

using namespace gismo;


int main(int argc, char *argv[]) {

  // Constants for input file and description
  // std::string INPUT_FILE = "breps/other/TUDflame.xml";
  std::string INPUT_FILE = "surfaces/teapot.xml";
  const std::string DESCRIPTION = "Hi, give me a file (eg: .xml) containing multi-patch and I will try to parameterize it!";

  // Load XML file - multi-patch computational domain
  //! [Read geometry]
  // Check if the input file exists
  if (!gsFileManager::fileExists(INPUT_FILE)) {
    gsWarn << "The file cannot be found!\n";
    return EXIT_FAILURE;
  }

  // MultiPatch reader
  gsInfo << "Read file \"" << INPUT_FILE << "\"\n";
  gsMultiPatch<real_t>::uPtr mp = gsReadFile<>(INPUT_FILE);
  gsInfo << " Got" << *mp << " \n";
  //! [Read geometry]

  // writeOcctIgesMp(const gsMultiPatch<real_t> & mp, const std::string & name)

  extensions::writeOcctIgesMp(*mp, "car");
  gsInfo << "Writing file \"" << INPUT_FILE << "\"\n";




  // // read from an IGES file
  // // std::string IGES_FILE = "/Users/jiye/Documents/mygithub_repositories/gismo_branches/gismo_iges_converter/cmake-build-relwithdebinfo/bin/teapot_freecad.iges";
  // // bool gsFileData<T>::readBrepFile( String const & fn )
  // std::string BREP_FILE = "/Users/jiye/Documents/mygithub_repositories/gismo_branches/gismo_iges_converter/cmake-build-relwithdebinfo/bin/teapot_freecad.brep";
  // gsFileData<> brep_data;
  // brep_data.readBrepFile(BREP_FILE);



  // // const char * BREP_FILE = "/Users/jiye/Documents/mygithub_repositories/gismo_branches/gismo_iges_converter/cmake-build-relwithdebinfo/bin/teapot_freecad.brep";
  //
  // // bool gsReadBrep( const char * filename, internal::gsXmlTree & data)
  // internal::gsXmlTree brep_geometry{};
  // extensions::gsReadBrep(BREP_FILE, brep_geometry);
  // gsInfo << "brep_geometry = \"" << brep_geometry << "\"\n";


  gsMultiPatch<> mp_from_iges;
  // std::string IGES_IMPORT_FILE = "/Users/jiye/Documents/mygithub_repositories/gismo_branches/gismo_iges_converter/cmake-build-relwithdebinfo/bin/teapot_freecad.iges";
  std::string IGES_IMPORT_FILE = "/Users/jiye/Documents/mygithub_repositories/gismo_branches/gismo_iges_converter/cmake-build-relwithdebinfo/bin/teapot_from_rhino_edited.igs";
  extensions::readOcctIgesMp(mp_from_iges, IGES_IMPORT_FILE, false, 1.0);
  gsInfo << "mp_from_iges = \"" << mp_from_iges << "\"\n";
  gsWriteParaview(mp_from_iges, "teapot_mp_from_rhino");

  // bool readOcctIgesMp(gsMultiPatch<real_t> & mp,
  //                   const std::string & igsFile,
  //                   bool importCurves = false,
  //                   real_t scale = 1.0)



  return EXIT_SUCCESS;
}