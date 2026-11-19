// ignore_for_file: file_names
import 'dart:io';

import 'package:arxiv/services/pdf_cache_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:ionicons_plus/ionicons_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

class PDFViewer extends StatefulWidget {
  const PDFViewer({
    super.key,
    required this.paperTitle,
    required this.savePath,
    required this.pdfURL,
    required this.urlType,
    required this.downloadPaper,
  });

  final String paperTitle;
  final String savePath;
  final String pdfURL;
  final int urlType;
  final Function downloadPaper;

  @override
  State<PDFViewer> createState() => _PDFViewerState();
}

class _PDFViewerState extends State<PDFViewer> {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      followRedirects: true,
      maxRedirects: 5,
      headers: const {
        "User-Agent": "ArxivPocket/1.0 (+https://github.com/enYao39/ArxivPocket)",
        "Accept": "application/pdf,*/*",
      },
    ),
  );

  bool _isLoading = true;
  bool _isReady = false;
  double? _progress;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _preparePdf();
  }

  @override
  void dispose() {
    _dio.close(force: true);
    super.dispose();
  }

  Future<bool> _isValidPdfFile(File file) async {
    if (!await file.exists()) return false;
    final length = await file.length();
    if (length <= 1024) return false;
    final raf = await file.open();
    try {
      final header = await raf.read(5);
      return header.length == 5 && String.fromCharCodes(header) == '%PDF-';
    } finally {
      await raf.close();
    }
  }

  Future<void> _preparePdf({bool forceDownload = false}) async {
    setState(() {
      _isLoading = true;
      _isReady = false;
      _progress = null;
      _errorMessage = null;
    });

    final targetFile = File(widget.savePath);
    if (!forceDownload && await _isValidPdfFile(targetFile)) {
      await PdfCacheStore().touchCachedFile(targetFile);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isReady = true;
      });
      return;
    }

    final tempFile = File('${widget.savePath}.part');
    try {
      await targetFile.parent.create(recursive: true);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      await _dio.download(
        widget.pdfURL,
        tempFile.path,
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _progress = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
          });
        },
      );

      if (!await _isValidPdfFile(tempFile)) {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        throw const FormatException('Downloaded file is not a valid PDF.');
      }

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);
      await PdfCacheStore().enforceLimit(protectedPath: targetFile.path);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isReady = true;
      });
    } catch (e) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isReady = false;
        _errorMessage = 'Could not load PDF: $e';
      });
    }
  }

  String _abstractUrlFor(String pdfUrl) {
    return pdfUrl
        .replaceFirst('/pdf/', '/abs/')
        .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.paperTitle, style: const TextStyle(fontSize: 16.0)),
        actions: [
          IconButton(
            tooltip: "Open abstract on arXiv",
            onPressed: () {
              launchUrl(Uri.parse(_abstractUrlFor(widget.pdfURL)));
            },
            icon: const Icon(Icons.open_in_browser_outlined),
          ),
          IconButton(
            tooltip: "Share PDF link",
            onPressed: () {
              Share.share(widget.pdfURL);
            },
            icon: const Icon(Ionicons.share_outline),
          ),
          IconButton(
            tooltip: "Download PDF",
            onPressed: () => {widget.downloadPaper(widget.pdfURL)},
            icon: const Icon(Icons.downloading_outlined),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(value: _progress),
              const SizedBox(height: 16.0),
              Text(
                _progress == null
                    ? "Loading PDF..."
                    : "Downloading PDF (${(_progress! * 100).round()}%)",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null || !_isReady) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 48.0,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12.0),
              Text(
                _errorMessage ?? 'Unable to open PDF.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16.0),
              Wrap(
                spacing: 12.0,
                runSpacing: 8.0,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => _preparePdf(forceDownload: true),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text("Retry"),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(widget.pdfURL)),
                    icon: const Icon(Icons.open_in_browser_outlined),
                    label: const Text("Open in browser"),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return SfPdfViewer.file(
        File(widget.savePath),
        onDocumentLoadFailed: (details) {
          if (!mounted) return;
          setState(() {
            _isReady = false;
            _errorMessage = 'Failed to render PDF: ${details.description}';
          });
        },
      );
    }

    return PDFView(
      filePath: widget.savePath,
      autoSpacing: false,
      pageFling: false,
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isReady = false;
          _errorMessage = 'Failed to render PDF: $error';
        });
      },
      onPageError: (page, error) {
        if (!mounted) return;
        setState(() {
          _isReady = false;
          _errorMessage = 'Failed to render page $page: $error';
        });
      },
    );
  }
}
