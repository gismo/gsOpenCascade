// main.mm (Qt6 + QOpenGLWindow + OCCT, macOS) - FIX: no-mouse-needed display

#include <QApplication>
#include <QMainWindow>
#include <QToolBar>
#include <QAction>
#include <QFileDialog>
#include <QMessageBox>
#include <QDialog>
#include <QDir>

#include <QOpenGLWindow>
#include <QWidget>
#include <QMouseEvent>
#include <QWheelEvent>
#include <QTimer>

#include <iostream>
#include <string>

// OCCT viewer / AIS
#include <TopoDS_Shape.hxx>
#include <AIS_InteractiveContext.hxx>
#include <AIS_Shape.hxx>
#include <V3d_Viewer.hxx>
#include <V3d_View.hxx>
#include <OpenGl_GraphicDriver.hxx>
#include <Aspect_DisplayConnection.hxx>
#include <Graphic3d_GraphicDriver.hxx>
#include <Quantity_Color.hxx>

// bbox + compound
#include <BRep_Builder.hxx>
#include <TopoDS_Compound.hxx>
#include <BRepBndLib.hxx>
#include <Bnd_Box.hxx>

// IO
#include <STEPControl_Reader.hxx>
#include <IGESControl_Reader.hxx>
#include <IFSelect_ReturnStatus.hxx>

// sanity
#include <BRepPrimAPI_MakeBox.hxx>

// Window abstraction for native handle
#include <Aspect_NeutralWindow.hxx>

// -----------------------------------------------------------------------------
// Robust STEP/IGES loader: collect all shapes into a compound
// -----------------------------------------------------------------------------
static TopoDS_Shape loadStepOrIgesVerbose(const std::string& path)
{
    auto endsWith = [](const std::string& s, const std::string& suf)
    {
        return s.size() >= suf.size() &&
               s.compare(s.size() - suf.size(), suf.size(), suf) == 0;
    };

    auto makeCompoundFromShapes = [](auto& reader) -> TopoDS_Shape
    {
        TopoDS_Compound comp;
        BRep_Builder b;
        b.MakeCompound(comp);

        const int n = reader.NbShapes();
        std::cerr << "[IO] NbShapes = " << n << "\n";
        for (int i = 1; i <= n; ++i)
        {
            const TopoDS_Shape s = reader.Shape(i);
            if (!s.IsNull())
                b.Add(comp, s);
        }
        return comp;
    };

    if (endsWith(path, ".stp") || endsWith(path, ".step") ||
        endsWith(path, ".STP") || endsWith(path, ".STEP"))
    {
        STEPControl_Reader r;
        const IFSelect_ReturnStatus stat = r.ReadFile(path.c_str());
        std::cerr << "[IO] STEP ReadFile status = " << int(stat) << "\n";
        if (stat != IFSelect_RetDone) return {};

        std::cerr << "[IO] STEP NbRootsForTransfer = " << r.NbRootsForTransfer() << "\n";
        r.TransferRoots();
        return makeCompoundFromShapes(r);
    }

    if (endsWith(path, ".igs") || endsWith(path, ".iges") ||
        endsWith(path, ".IGS") || endsWith(path, ".IGES"))
    {
        IGESControl_Reader r;
        const IFSelect_ReturnStatus stat = r.ReadFile(path.c_str());
        std::cerr << "[IO] IGES ReadFile status = " << int(stat) << "\n";
        if (stat != IFSelect_RetDone) return {};

        r.TransferRoots();
        return makeCompoundFromShapes(r);
    }

    std::cerr << "[IO] Unsupported extension: " << path << "\n";
    return {};
}

// -----------------------------------------------------------------------------
// OCCT inside QOpenGLWindow (more reliable than QOpenGLWidget on macOS)
// -----------------------------------------------------------------------------
class OcctGLWindow final : public QOpenGLWindow
{
public:
    OcctGLWindow()
        : QOpenGLWindow(QOpenGLWindow::NoPartialUpdate)
    {
        setTitle("OCCT View");
        setSurfaceType(QSurface::OpenGLSurface);

        // Burst timer to "settle" after fit/load/resize
        m_burstTimer.setTimerType(Qt::PreciseTimer);
        connect(&m_burstTimer, &QTimer::timeout, this, [this]()
        {
            if (m_burstFramesLeft > 0)
            {
                m_forceRedraw = true;
                requestUpdate(); // triggers render()
                --m_burstFramesLeft;
            }
            else
            {
                m_burstTimer.stop();
            }
        });
    }

    bool isReady() const { return !m_view.IsNull() && !m_ctx.IsNull(); }

    void displayShape(const TopoDS_Shape& shape, bool fit = true)
    {
        if (!isReady())
        {
            std::cerr << "[VIEW] displayShape before init\n";
            return;
        }
        if (shape.IsNull())
        {
            std::cerr << "[VIEW] shape is NULL\n";
            return;
        }

        // bbox debug
        Bnd_Box bb;
        BRepBndLib::Add(shape, bb);
        if (!bb.IsVoid())
        {
            Standard_Real xmin, ymin, zmin, xmax, ymax, zmax;
            bb.Get(xmin, ymin, zmin, xmax, ymax, zmax);
            std::cerr << "[VIEW] BBox: ["
                      << xmin << "," << ymin << "," << zmin << "] - ["
                      << xmax << "," << ymax << "," << zmax << "]\n";
        }

        m_ctx->RemoveAll(Standard_False);

        Handle(AIS_Shape) ais = new AIS_Shape(shape);
        m_ctx->Display(ais, Standard_False);
        m_ctx->SetDisplayMode(ais, AIS_Shaded, Standard_False);
        m_ctx->UpdateCurrentViewer();

        if (fit)
        {
            m_view->FitAll();
            m_view->ZFitAll();
        }

        requestBurstRedraw(6);
    }

protected:
    void initializeGL() override
    {
        std::cerr << "[OCCT] initializeGL\n";

        Handle(Aspect_DisplayConnection) dc = new Aspect_DisplayConnection();
        Handle(Graphic3d_GraphicDriver) gd = new OpenGl_GraphicDriver(dc);

        m_viewer = new V3d_Viewer(gd);
        m_viewer->SetDefaultLights();
        m_viewer->SetLightOn();

        m_ctx  = new AIS_InteractiveContext(m_viewer);
        m_view = m_viewer->CreateView();

        // Bind OCCT to native handle
        m_wnd = new Aspect_NeutralWindow();
        m_wnd->SetVirtual(Standard_False);
        m_wnd->SetNativeHandle((Aspect_Drawable)winId());

        syncOcctWindow(/*forceMap=*/true);

        m_view->SetWindow(m_wnd);
        if (!m_view->Window()->IsMapped())
            m_view->Window()->Map();

        m_view->SetBackgroundColor(Quantity_NOC_GRAY90);
        m_view->TriedronDisplay(Aspect_TOTP_LEFT_LOWER, Quantity_NOC_GRAY30, 0.08, V3d_ZBUFFER);
        m_view->MustBeResized();

        std::cerr << "[OCCT] viewer ready\n";

        // Sanity box (should appear without any mouse movement)
        displayShape(BRepPrimAPI_MakeBox(100, 80, 60).Shape(), true);
    }

    void resizeGL(int w, int h) override
    {
        QOpenGLWindow::resizeGL(w, h);
        if (!m_view.IsNull())
        {
            syncOcctWindow(/*forceMap=*/false);
            m_view->MustBeResized();
            requestBurstRedraw(4);
        }
    }

    void paintGL() override
    {
        if (m_view.IsNull())
            return;

        // ensure size is synced (important on macOS with dpr changes)
        syncOcctWindow(/*forceMap=*/false);

        // OCCT draw
        if (m_forceRedraw)
        {
            m_view->Invalidate();
            m_view->Redraw();
            m_forceRedraw = false;
        }
        else
        {
            // One redraw is cheap and keeps stable
            m_view->Redraw();
        }
    }

    // ---- dpr-correct mouse coords ----
    void mousePressEvent(QMouseEvent* e) override
    {
        m_last = e->pos();

        if (!m_ctx.IsNull() && !m_view.IsNull())
        {
            const qreal dpr = devicePixelRatio();
            const int px = int(e->position().x() * dpr);
            const int py = int(e->position().y() * dpr);
            m_ctx->MoveTo(px, py, m_view, Standard_False);
        }

        requestBurstRedraw(2);
    }

    void mouseMoveEvent(QMouseEvent* e) override
    {
        if (m_view.IsNull()) return;

        const QPoint cur = e->pos();
        const int dx = cur.x() - m_last.x();
        const int dy = cur.y() - m_last.y();

        const qreal dpr = devicePixelRatio();
        const int curX = int(cur.x() * dpr);
        const int curY = int(cur.y() * dpr);
        const int lastX = int(m_last.x() * dpr);
        const int lastY = int(m_last.y() * dpr);

        if (e->buttons() & Qt::LeftButton)
        {
            if (!m_rotating)
            {
                m_view->StartRotation(lastX, lastY);
                m_rotating = true;
            }
            m_view->Rotation(curX, curY);
        }
        else
        {
            m_rotating = false;

            if (e->buttons() & Qt::RightButton)
                m_view->Pan(int(dx * dpr), int(-dy * dpr));

            if (!m_ctx.IsNull())
                m_ctx->MoveTo(curX, curY, m_view, Standard_False);
        }

        m_last = cur;
        requestBurstRedraw(1);
    }

    void mouseReleaseEvent(QMouseEvent* e) override
    {
        QOpenGLWindow::mouseReleaseEvent(e);
        m_rotating = false;
        requestBurstRedraw(2);
    }

    void wheelEvent(QWheelEvent* e) override
    {
        if (m_view.IsNull()) return;

        const qreal dpr = devicePixelRatio();
        const QPointF lp = e->position();
        const int px = int(lp.x() * dpr);
        const int py = int(lp.y() * dpr);

        const int delta = e->angleDelta().y();
        const int step = (delta > 0) ? 120 : -120;

        m_view->StartZoomAtPoint(px, py);
        m_view->ZoomAtPoint(px, py, px, py + int(step * dpr));

        requestBurstRedraw(2);
    }

private:
    void requestBurstRedraw(int frames)
    {
        if (frames <= 0) return;
        m_burstFramesLeft = std::max(m_burstFramesLeft, frames);
        m_forceRedraw = true;
        if (!m_burstTimer.isActive())
            m_burstTimer.start(16); // ~60 fps during burst only
        requestUpdate();
    }

    void syncOcctWindow(bool forceMap)
    {
        if (m_wnd.IsNull())
            return;

        const qreal dpr = devicePixelRatio();
        const int pxW = std::max(1, int(width()  * dpr));
        const int pxH = std::max(1, int(height() * dpr));

        m_wnd->SetSize(pxW, pxH);
        m_wnd->SetPosition(0, 0);

        if (forceMap && !m_wnd->IsMapped())
            m_wnd->Map();
    }

private:
    bool m_rotating = false;
    QPoint m_last;

    bool m_forceRedraw = true;

    QTimer m_burstTimer;
    int m_burstFramesLeft = 0;

    Handle(V3d_Viewer) m_viewer;
    Handle(V3d_View) m_view;
    Handle(AIS_InteractiveContext) m_ctx;
    Handle(Aspect_NeutralWindow) m_wnd;
};

// -----------------------------------------------------------------------------
int main(int argc, char** argv)
{
    QApplication app(argc, argv);

    QMainWindow win;
    win.setWindowTitle("OCCT + Qt6 Viewer (macOS) - QOpenGLWindow Container Alberto Biliotti, Dimitrios Tolis, Felix Scholz, Ye Ji, G+Smo developer days, Pilsen, Czech Republic 2026");

    // Create OpenGL window + wrap as QWidget
    auto* glWin = new OcctGLWindow();
    QWidget* viewerWidget = QWidget::createWindowContainer(glWin, &win);
    viewerWidget->setFocusPolicy(Qt::StrongFocus);

    win.setCentralWidget(viewerWidget);

    QToolBar* tb = win.addToolBar("Main");
    QAction* actOpen = tb->addAction("Open STEP/IGES");

    QObject::connect(actOpen, &QAction::triggered, [&]()
    {
        win.raise();
        win.activateWindow();
        QApplication::processEvents();

        QFileDialog dlg(&win);
        dlg.setWindowTitle("Open STEP/IGES");
        dlg.setDirectory(QDir::homePath());
        dlg.setNameFilter("CAD Files (*.step *.stp *.iges *.igs);;All Files (*)");
        dlg.setFileMode(QFileDialog::ExistingFile);
        dlg.setOption(QFileDialog::DontUseNativeDialog, true);
        dlg.setWindowModality(Qt::ApplicationModal);

        if (dlg.exec() != QDialog::Accepted)
            return;

        const QString path = dlg.selectedFiles().value(0);
        if (path.isEmpty())
            return;

        std::cerr << "[UI] Selected: " << path.toStdString() << "\n";

        TopoDS_Shape shp = loadStepOrIgesVerbose(path.toStdString());
        if (shp.IsNull())
        {
            QMessageBox::critical(&win, "Load failed",
                                  "OCCT could not read that file.\n"
                                  "Check STEP/IGES format.");
            return;
        }

        glWin->displayShape(shp, true);
    });

    win.resize(1200, 800);
    win.show();

    win.raise();
    win.activateWindow();
    QApplication::processEvents();

    return app.exec();
}
