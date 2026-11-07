use std::{slice, sync::OnceLock};
use typst::{World, Library, foundations::{Bytes, Datetime}, syntax::{FileId, Source, VirtualPath}, text::{Font, FontBook}, utils::LazyHash, diag::{FileError, FileResult}, layout::PagedDocument};

struct ReportWorld {
    library: LazyHash<Library>,
    book: LazyHash<FontBook>,
    fonts: Vec<Font>,
    source: Source,
    json: Bytes,
}

impl World for ReportWorld {
    fn library(&self) -> &LazyHash<Library> { &self.library }
    fn book(&self) -> &LazyHash<FontBook> { &self.book }
    fn main(&self) -> FileId { self.source.id() }
    fn source(&self, id: FileId) -> FileResult<Source> {
        if id == self.source.id() { Ok(self.source.clone()) } else { Err(FileError::AccessDenied) }
    }
    fn file(&self, id: FileId) -> FileResult<Bytes> {
        if id.package().is_none() && id.vpath().as_rooted_path().to_str() == Some("/report.json") { Ok(self.json.clone()) }
        else { Err(FileError::AccessDenied) }
    }
    fn font(&self, index: usize) -> Option<Font> { self.fonts.get(index).cloned() }
    fn today(&self, _: Option<i64>) -> Option<Datetime> { None }
}

fn compile(source: &str, json: &[u8]) -> Result<Vec<u8>, String> {
    static FONTS: OnceLock<Vec<Font>> = OnceLock::new();
    let fonts = FONTS.get_or_init(|| typst_assets::fonts().chain([
        include_bytes!("../fonts/Lato-Regular.ttf").as_slice(),
        include_bytes!("../fonts/Lato-Bold.ttf").as_slice(),
    ]).flat_map(|data| Font::iter(Bytes::new(data))).collect()).clone();
    let world = ReportWorld {
        library: LazyHash::new(Library::builder().build()),
        book: LazyHash::new(FontBook::from_fonts(&fonts)), fonts,
        source: Source::new(FileId::new(None, VirtualPath::new("/main.typ")), source.to_owned()),
        json: Bytes::new(json.to_vec()),
    };
    let document = typst::compile::<PagedDocument>(&world).output.map_err(|errors| errors.iter().map(|e| e.message.to_string()).collect::<Vec<_>>().join("\n"))?;
    typst_pdf::pdf(&document, &typst_pdf::PdfOptions::default()).map_err(|errors| errors.iter().map(|e| e.message.to_string()).collect::<Vec<_>>().join("\n"))
}

/// Produces an owned byte buffer (PDF on success, UTF-8 diagnostic on failure).
/// Callers supply valid readable inputs and writable out parameters, then free once.
#[no_mangle]
pub unsafe extern "C" fn harbour_typst_compile(source: *const u8, source_len: usize, json: *const u8, json_len: usize, output: *mut *mut u8, output_len: *mut usize) -> i32 {
    let result = std::panic::catch_unwind(|| {
        let source = std::str::from_utf8(slice::from_raw_parts(source, source_len)).map_err(|_| "Invalid template encoding".to_string())?;
        compile(source, slice::from_raw_parts(json, json_len))
    }).unwrap_or_else(|_| Err("Report renderer failed".into()));
    // Reports are independent snapshots. Release memoized document data after each
    // render instead of retaining personal text across successive compilations.
    comemo::evict(0);
    let (status, bytes) = match result { Ok(pdf) => (0, pdf), Err(message) => (1, message.into_bytes()) };
    let mut bytes = bytes.into_boxed_slice();
    *output_len = bytes.len(); *output = bytes.as_mut_ptr(); std::mem::forget(bytes); status
}

#[no_mangle]
pub unsafe extern "C" fn harbour_typst_free(bytes: *mut u8, len: usize) {
    if !bytes.is_null() { drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(bytes, len))); }
}
