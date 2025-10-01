package com.lxmoon.image_ocr

import com.bumptech.glide.annotation.GlideModule
import com.bumptech.glide.module.AppGlideModule

/**
 * A generated AppGlideModule to silence the warning about missing modules.
 * This class is required for Glide's annotation processor to work correctly.
 */
@GlideModule
class MyAppGlideModule : AppGlideModule() {
    // isManifestParsingEnabled should be disabled to avoid potential conflicts
    // with other libraries that might also provide Glide modules.
    override fun isManifestParsingEnabled(): Boolean {
        return false
    }
}