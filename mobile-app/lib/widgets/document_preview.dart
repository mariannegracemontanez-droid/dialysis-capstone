import 'package:flutter/material.dart';

/// One uploaded medical document image.
class DocumentPreviewItem {
  final String label;
  final String url;

  const DocumentPreviewItem({required this.label, required this.url});
}

/// Opens a full-screen viewer for [documents], starting at [initialIndex].
/// Swipe between documents, pinch to zoom; images keep their proportions.
Future<void> showDocumentPreview(
  BuildContext context, {
  required List<DocumentPreviewItem> documents,
  int initialIndex = 0,
}) {
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    barrierColor: Colors.black,
    builder: (_) => _DocumentPreviewDialog(
      documents: documents,
      initialIndex: initialIndex.clamp(0, documents.length - 1),
    ),
  );
}

class _DocumentPreviewDialog extends StatefulWidget {
  final List<DocumentPreviewItem> documents;
  final int initialIndex;

  const _DocumentPreviewDialog({
    required this.documents,
    required this.initialIndex,
  });

  @override
  State<_DocumentPreviewDialog> createState() => _DocumentPreviewDialogState();
}

class _DocumentPreviewDialogState extends State<_DocumentPreviewDialog> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final documents = widget.documents;
    final current = documents[_index];

    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (documents.length > 1)
                          Text(
                            '${_index + 1} of ${documents.length}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: documents.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) {
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image.network(
                        documents[index].url,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : const CircularProgressIndicator(
                                color: Colors.white,
                              ),
                        errorBuilder: (context, error, stackTrace) =>
                            const _PreviewError(),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (documents.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Previous document',
                      onPressed: _index == 0
                          ? null
                          : () => _pageController.previousPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            ),
                      icon: const Icon(Icons.chevron_left_rounded),
                      color: Colors.white,
                      disabledColor: Colors.white24,
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      tooltip: 'Next document',
                      onPressed: _index == documents.length - 1
                          ? null
                          : () => _pageController.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            ),
                      icon: const Icon(Icons.chevron_right_rounded),
                      color: Colors.white,
                      disabledColor: Colors.white24,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48),
          SizedBox(height: 12),
          Text(
            'Unable to load this document.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// Small square image of a document, with a placeholder when it can't load.
class DocumentThumbnail extends StatelessWidget {
  final String url;
  final double size;

  const DocumentThumbnail({super.key, required this.url, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          color: const Color(0xFFF4F8FA),
          child: const Icon(
            Icons.image_not_supported_outlined,
            color: Color(0xFF5F7280),
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrollable row of labelled document thumbnails; tapping one
/// opens [showDocumentPreview] at that document.
class DocumentGallery extends StatelessWidget {
  final List<DocumentPreviewItem> documents;

  const DocumentGallery({super.key, required this.documents});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: documents.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final document = documents[index];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => showDocumentPreview(
              context,
              documents: documents,
              initialIndex: index,
            ),
            child: SizedBox(
              width: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DocumentThumbnail(url: document.url, size: 96),
                  const SizedBox(height: 6),
                  Text(
                    document.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF173B4F),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
