package com.aidocassistant.app.pdfimport;

import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.print.PageRange;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintDocumentInfo;

/**
 * Java helper to work around Kotlin 2.x enforcing package-private access on
 * PrintDocumentAdapter.LayoutResultCallback and WriteResultCallback constructors.
 * Java doesn't enforce this restriction in practice (the classes are abstract
 * and designed to be subclassed by the framework, but the callback objects are
 * passed TO user code via onLayout/onWrite).
 *
 * Instead of subclassing the callbacks (impossible), we invoke onLayout/onWrite
 * from Java where the compiler allows passing anonymous implementations.
 */
public final class PrintCallbackFactory {

    public interface LayoutListener {
        void onFinished(PrintDocumentInfo info, boolean changed);
        void onFailed(CharSequence error);
    }

    public interface WriteListener {
        void onFinished(PageRange[] pages);
        void onFailed(CharSequence error);
    }

    public static void invokeLayout(
            PrintDocumentAdapter adapter,
            PrintAttributes oldAttrs,
            PrintAttributes newAttrs,
            CancellationSignal cancel,
            LayoutListener listener,
            Bundle extras
    ) {
        adapter.onLayout(oldAttrs, newAttrs, cancel,
                new PrintDocumentAdapter.LayoutResultCallback() {
                    @Override
                    public void onLayoutFinished(PrintDocumentInfo info, boolean changed) {
                        listener.onFinished(info, changed);
                    }
                    @Override
                    public void onLayoutFailed(CharSequence error) {
                        listener.onFailed(error);
                    }
                }, extras);
    }

    public static void invokeWrite(
            PrintDocumentAdapter adapter,
            PageRange[] pages,
            ParcelFileDescriptor destination,
            CancellationSignal cancel,
            WriteListener listener
    ) {
        adapter.onWrite(pages, destination, cancel,
                new PrintDocumentAdapter.WriteResultCallback() {
                    @Override
                    public void onWriteFinished(PageRange[] writtenPages) {
                        listener.onFinished(writtenPages);
                    }
                    @Override
                    public void onWriteFailed(CharSequence error) {
                        listener.onFailed(error);
                    }
                });
    }
}
