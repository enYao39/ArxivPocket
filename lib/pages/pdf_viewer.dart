// ignore_for_file: file_names
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
      body: widget.urlType == 1
          ? SfPdfViewer.network(widget.pdfURL, enableTextSelection: true)
          : PDFView(
              filePath: widget.savePath,
              autoSpacing: false,
              pageFling: false,
            ),
    );
  }
}
