using System.Windows;

namespace MCGA
{
    public partial class TrayIconView : System.Windows.Controls.UserControl
    {
        public TrayIconView()
        {
            InitializeComponent();
        }

        private void OnTrayLeftMouseDown(object sender, RoutedEventArgs e)
        {
            ((App)Application.Current).ShowPopover();
        }

        private void OnSettingsClick(object sender, RoutedEventArgs e)
        {
            ((App)Application.Current).ShowSettings();
        }

        private void OnQuitClick(object sender, RoutedEventArgs e)
        {
            Application.Current.Shutdown();
        }
    }
}