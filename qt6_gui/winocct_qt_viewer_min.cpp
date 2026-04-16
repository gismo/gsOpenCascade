// main.cpp — Qt6 + OCCT cross-platform viewer (WORKING)

#include <QApplication>
#include <QMainWindow>
#include <QToolBar>
#include <QAction>
#include <QFileDialog>
#include <QMessageBox>
#include <QSurfaceFormat>
#include <QOpenGLWindow>
#include <QWidget>
#include <QMouseEvent>
#include <QWheelEvent>

// OCCT
#include <AIS_InteractiveContext.hxx>
#include <AIS_Shape.hxx>
#include <V3d_Viewer.hxx>
#include <V3d_View.hxx>
#include <OpenGl_GraphicDriver.hxx>
#include <Aspect_DisplayConnection.hxx>
#include <Aspect_NeutralWindow.hxx>

#include <BRepPrimAPI_MakeBox.hxx>
#include <STEPControl_Reader.hxx>
#include <IGESControl_Reader.hxx>
#include <IFSelect_ReturnStatus.hxx>

// ----------------------------------------------------------------------------
// OCCT OpenGL Window (CORRECT APPROACH)
// ----------------------------------------------------------------------------
class OcctWindow : public QOpenGLWindow
{
public:
    OcctWindow() : QOpenGLWindow(QOpenGLWindow::NoPartialUpdate) {}

    void displayShape(const TopoDS_Shape& shape)
    {
        if (m_ctx.IsNull() || shape.IsNull())
            return;

        m_ctx->RemoveAll(false);

        Handle(AIS_Shape) ais = new AIS_Shape(shape);
        m_ctx->Display(ais, false);
        m_ctx->SetDisplayMode(ais, AIS_Shaded, false);

        m_ctx->UpdateCurrentViewer();

        m_view->FitAll();
        m_view->ZFitAll();

        requestUpdate();
    }

protected:
    void initializeGL() override
    {
        Handle(Aspect_DisplayConnection) dc = new Aspect_DisplayConnection();
        Handle(OpenGl_GraphicDriver) gd = new OpenGl_GraphicDriver(dc);

        m_viewer = new V3d_Viewer(gd);
        m_viewer->SetDefaultLights();
        m_viewer->SetLightOn();

        m_ctx = new AIS_InteractiveContext(m_viewer);
        m_view = m_viewer->CreateView();

        m_window = new Aspect_NeutralWindow();
        m_window->SetNativeHandle((Aspect_Drawable)winId());

        m_view->SetWindow(m_window);

        if (!m_window->IsMapped())
            m_window->Map();

        m_view->SetBackgroundColor(Quantity_NOC_GRAY90);
        m_view->SetProj(V3d_Zpos);
        m_view->MustBeResized();


        displayShape(BRepPrimAPI_MakeBox(100, 80, 60).Shape());
    }

    void resizeGL(int w, int h) override
    {
        if (!m_view.IsNull())
        {
            const qreal dpr = devicePixelRatio();
            m_window->SetSize(int(w * dpr), int(h * dpr));
            m_view->MustBeResized();
        }
    }

    void paintGL() override
    {
        if (!m_view.IsNull())
        {
            m_view->Invalidate();
            m_view->Redraw();
        }
    }

    // --- basic interaction ---
    void mousePressEvent(QMouseEvent* e) override
    {
        m_last = e->pos();
    }

    void mouseMoveEvent(QMouseEvent* e) override
    {
        if (m_view.IsNull()) return;

        QPoint cur = e->pos();
        int dx = cur.x() - m_last.x();
        int dy = cur.y() - m_last.y();

        if (e->buttons() & Qt::LeftButton)
        {
            if (!m_rotating)
            {
                m_view->StartRotation(m_last.x(), m_last.y());
                m_rotating = true;
            }
            m_view->Rotation(cur.x(), cur.y());
        }
        else if (e->buttons() & Qt::RightButton)
        {
            m_view->Pan(dx, -dy);
            m_rotating = false;
        }

        m_last = cur;
        requestUpdate();
    }

    void mouseReleaseEvent(QMouseEvent*) override
    {
        m_rotating = false;
    }

    void wheelEvent(QWheelEvent* e) override
    {
        if (m_view.IsNull()) return;

        int delta = e->angleDelta().y();

        if (delta > 0)
            m_view->SetZoom(0.9);
        else
            m_view->SetZoom(1.1);

        requestUpdate();
    }

private:
    QPoint m_last;
    bool m_rotating = false;

    Handle(V3d_Viewer) m_viewer;
    Handle(V3d_View) m_view;
    Handle(AIS_InteractiveContext) m_ctx;
    Handle(Aspect_NeutralWindow) m_window;
};

// ----------------------------------------------------------------------------
// CAD Loader
// ----------------------------------------------------------------------------
TopoDS_Shape loadCAD(const QString& path)
{
    if (path.endsWith(".step") || path.endsWith(".stp"))
    {
        STEPControl_Reader reader;
        if (reader.ReadFile(path.toStdString().c_str()) != IFSelect_RetDone)
            return {};
        reader.TransferRoots();
        return reader.OneShape();
    }
    else if (path.endsWith(".iges") || path.endsWith(".igs"))
    {
        IGESControl_Reader reader;
        if (reader.ReadFile(path.toStdString().c_str()) != IFSelect_RetDone)
            return {};
        reader.TransferRoots();
        return reader.OneShape();
    }
    return {};
}

// ----------------------------------------------------------------------------
// MAIN
// ----------------------------------------------------------------------------
int main(int argc, char** argv)
{
    // 🔥 Force real OpenGL
    QCoreApplication::setAttribute(Qt::AA_UseDesktopOpenGL);

    QSurfaceFormat fmt;
    fmt.setDepthBufferSize(24);
    fmt.setStencilBufferSize(8);
    fmt.setVersion(2, 1);
    fmt.setProfile(QSurfaceFormat::NoProfile);
    QSurfaceFormat::setDefaultFormat(fmt);

    QApplication app(argc, argv);

    QMainWindow win;

    // 🔥 CORRECT container usage
    auto* glWin = new OcctWindow();
    QWidget* container = QWidget::createWindowContainer(glWin);
    win.setCentralWidget(container);

    QToolBar* tb = win.addToolBar("Main");
    QAction* openAct = tb->addAction("Open");

    QObject::connect(openAct, &QAction::triggered, [&]()
    {
        QString file = QFileDialog::getOpenFileName(&win, "Open CAD", "", "CAD (*.step *.stp *.iges *.igs)");
        if (file.isEmpty()) return;

        TopoDS_Shape shape = loadCAD(file);
        if (shape.IsNull())
        {
            QMessageBox::critical(&win, "Error", "Failed to load file");
            return;
        }

        glWin->displayShape(shape);
    });

    win.resize(1200, 800);
    win.show();

    return app.exec();
}