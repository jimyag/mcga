using System.Windows;

namespace MCGA
{
    public partial class TrayIconView : System.Windows.Controls.UserControl
    {
        public TrayIconView()
        {
            InitializeComponent();
        }

        private void OnSettingsClick(object sender, RoutedEventArgs e)
        {
            MessageBox.Show("Settings window will be implemented in a future phase.", "MCGA Settings");
        }

        private void OnQuitClick(object sender, RoutedEventArgs e)
        {
            Application.Current.Shutdown();
        }
    }
}