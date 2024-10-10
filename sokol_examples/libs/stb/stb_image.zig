// flip the image vertically, so the first pixel in the output array is the bottom left
pub extern "c" fn stbi_set_flip_vertically_on_load(flag_true_if_should_flip: c_int) void;

pub extern "c" fn stbi_load_from_memory(buffer: [*c]const u8, len: c_int, x: *c_int, y: *c_int, comp: *c_int, req_comp: c_int) [*c]const u8;

pub extern "c" fn stbi_image_free(retval_from_stbi_load: *const anyopaque) void;
