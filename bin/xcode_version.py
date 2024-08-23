import argparse
import ctypes
import ctypes.util
from typing import NamedTuple
import plistlib

class XcodeVersion(NamedTuple):
    major: int
    minor: int
    patch: int
    beta: int
    build: str
    bundle: int

def xcode_version(developer_dir_path: str) -> XcodeVersion:
    objc = ctypes.cdll.LoadLibrary(ctypes.util.find_library('objc'))
    objc.objc_getClass.restype = ctypes.c_void_p
    objc.sel_registerName.restype = ctypes.c_void_p
    objc.objc_msgSend.restype = ctypes.c_void_p
    objc.objc_msgSend.argtypes = [ctypes.c_void_p, ctypes.c_void_p]

    ctypes.cdll.LoadLibrary(
        ('%s/../SharedFrameworks/DVTFoundation.framework/DVTFoundation') % developer_dir_path
    )
    NSAutoreleasePool = objc.objc_getClass('NSAutoreleasePool')
    pool = objc.objc_msgSend(NSAutoreleasePool, objc.sel_registerName('alloc'))
    pool = objc.objc_msgSend(pool, objc.sel_registerName('init'))

    tools_info = objc.objc_msgSend(
        objc.objc_getClass('DVTToolsInfo'.encode('utf8')),
        objc.sel_registerName('toolsInfo'.encode('utf8'))
    )
    tools_build_version = objc.objc_msgSend(
        tools_info,
        objc.sel_registerName('toolsBuildVersion'.encode('utf8'))
    )
    tools_version = objc.objc_msgSend(
        tools_info,
        objc.sel_registerName('toolsVersion'.encode('utf8'))
    )

    major_version_int = objc.objc_msgSend(
        tools_version,
        objc.sel_registerName('versionMajorComponent'.encode('utf8'))
    )
    if major_version_int is None:
        major_version_int = 0
    minor_version_int = objc.objc_msgSend(
        tools_version,
        objc.sel_registerName('versionMinorComponent'.encode('utf8'))
    )
    if minor_version_int is None:
        minor_version_int = 0
    patch_version_int = objc.objc_msgSend(
        tools_version,
        objc.sel_registerName('versionUpdateComponent'.encode('utf8'))
    )
    if patch_version_int is None:
        patch_version_int = 0

    is_beta = objc.objc_msgSend(
        tools_info,
        objc.sel_registerName('isBeta'.encode('utf8'))
    )
    is_beta_bool = bool(is_beta)
    beta_version_int = None
    if is_beta_bool:
        beta_version_int = objc.objc_msgSend(
            tools_info,
            objc.sel_registerName('toolsBetaVersion'.encode('utf8'))
        )

    build_version_bstr = ctypes.string_at(
        objc.objc_msgSend(
            objc.objc_msgSend(
                tools_build_version,
                objc.sel_registerName('name'.encode('utf8'))
            ),
            objc.sel_registerName('UTF8String'.encode('utf8'))
        )
    )
    build_version_str = build_version_bstr.decode('utf8')

    objc.objc_msgSend(pool, objc.sel_registerName('release'))

    bundle_version_str = None
    with open(('%s/../version.plist') % developer_dir_path, 'rb') as version_plist_file:
        plist = plistlib.load(version_plist_file)
        bundle_version_str = plist['CFBundleVersion']

    return XcodeVersion(
        major=major_version_int,
        minor=minor_version_int,
        patch=patch_version_int,
        beta=beta_version_int,
        build=build_version_str,
        bundle=bundle_version_str
    )

if __name__ == "__main__":
    parser = argparse.ArgumentParser("xcode_version")
    parser.add_argument(
        "developer_dir",
        help="Path to the developer directory of an Xcode to extract version information from.",
        type=str
    )
    args = parser.parse_args()

    print(
        xcode_version(
            developer_dir_path=args.developer_dir
        )
    )
