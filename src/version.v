module vmarkdown

import v.vmod

const vmod_info = vmod.decode(@VMOD_FILE) or { panic(err) }

pub const version = vmod_info.version
