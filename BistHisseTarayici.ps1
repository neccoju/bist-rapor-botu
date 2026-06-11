param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
[Threading.Thread]::CurrentThread.CurrentUICulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')

$modulePath = Join-Path $PSScriptRoot 'BistScanner.Core.psm1'
Import-Module $modulePath -Force

$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="BIST Hisse Tarayıcı"
    Width="1600"
    Height="900"
    MinWidth="1250"
    MinHeight="700"
    WindowStartupLocation="CenterScreen"
    Background="#F4F6FA"
    FontFamily="Segoe UI">
    <Window.Resources>
        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Background" Value="#2563EB"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#2563EB"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="16,9"/>
            <Setter Property="Margin" Value="6,0,0,0"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="Foreground" Value="#1E293B"/>
            <Setter Property="BorderBrush" Value="#CBD5E1"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="Margin" Value="6,0,0,0"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Height" Value="32"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="BorderBrush" Value="#CBD5E1"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Background" Value="White"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Height" Value="32"/>
            <Setter Property="Padding" Value="6,3"/>
            <Setter Property="BorderBrush" Value="#CBD5E1"/>
            <Setter Property="Background" Value="White"/>
        </Style>
        <Style x:Key="MetricLabel" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#64748B"/>
            <Setter Property="FontSize" Value="11"/>
        </Style>
        <Style x:Key="MetricValue" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#0F172A"/>
            <Setter Property="FontSize" Value="17"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="0,3,0,0"/>
        </Style>
        <Style x:Key="SectionTitle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#334155"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="0,14,0,8"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="#0F172A" Padding="22,18">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                    <TextBlock Text="BIST Hisse Tarayıcı" Foreground="White" FontSize="24" FontWeight="SemiBold"/>
                    <TextBlock Text="Tüm BIST hisseleri için açıklanabilir karar-destek puanları | Yeni bilançolar 30 dakikada bir kontrol edilir" Foreground="#94A3B8" FontSize="12" Margin="0,4,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock x:Name="txtBusy" Text="Veri alınıyor..." Foreground="#BFDBFE" VerticalAlignment="Center" Margin="0,0,10,0" Visibility="Collapsed"/>
                    <Button x:Name="btnExport" Content="CSV Dışa Aktar" Style="{StaticResource SecondaryButton}"/>
                    <Button x:Name="btnOpenChart" Content="Grafiği Aç" Style="{StaticResource SecondaryButton}" IsEnabled="False"/>
                    <Button x:Name="btnScan" Content="Tüm BIST'i Tara" Style="{StaticResource PrimaryButton}"/>
                </StackPanel>
            </Grid>
        </Border>

        <Border Grid.Row="1" Background="White" BorderBrush="#E2E8F0" BorderThickness="0,0,0,1" Padding="18,12">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="230"/>
                    <ColumnDefinition Width="145"/>
                    <ColumnDefinition Width="185"/>
                    <ColumnDefinition Width="220"/>
                    <ColumnDefinition Width="210"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Margin="0,0,12,0">
                    <TextBlock Text="Ara" Foreground="#64748B" FontSize="11" Margin="0,0,0,4"/>
                    <TextBox x:Name="txtSearch" ToolTip="Sembol, şirket, sektör veya endüstri ara"/>
                </StackPanel>

                <StackPanel Grid.Column="1" Margin="0,0,12,0">
                    <TextBlock Text="Strateji" Foreground="#64748B" FontSize="11" Margin="0,0,0,4"/>
                    <ComboBox x:Name="cmbStrategy">
                        <ComboBoxItem Content="Dengeli" IsSelected="True"/>
                        <ComboBoxItem Content="Değer"/>
                        <ComboBoxItem Content="Momentum"/>
                        <ComboBoxItem Content="Kalite"/>
                    </ComboBox>
                </StackPanel>

                <StackPanel Grid.Column="2" Margin="0,0,12,0">
                    <TextBlock Text="Minimum piyasa değeri" Foreground="#64748B" FontSize="11" Margin="0,0,0,4"/>
                    <ComboBox x:Name="cmbMarketCap">
                        <ComboBoxItem Content="Tümü" IsSelected="True"/>
                        <ComboBoxItem Content="1 milyar TL"/>
                        <ComboBoxItem Content="5 milyar TL"/>
                        <ComboBoxItem Content="10 milyar TL"/>
                        <ComboBoxItem Content="50 milyar TL"/>
                    </ComboBox>
                </StackPanel>

                <StackPanel Grid.Column="3" Margin="0,0,12,0">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="Minimum skor" Foreground="#64748B" FontSize="11"/>
                        <TextBlock x:Name="txtMinScore" Grid.Column="1" Text="0" Foreground="#334155" FontSize="11" FontWeight="SemiBold"/>
                    </Grid>
                    <Slider x:Name="sldMinScore" Minimum="0" Maximum="90" Value="0" TickFrequency="5" IsSnapToTickEnabled="True" Margin="0,7,0,0"/>
                </StackPanel>

                <StackPanel Grid.Column="4" VerticalAlignment="Bottom" Margin="0,0,12,6">
                    <CheckBox x:Name="chkIncludeHighRisk" Content="Yüksek risklileri dahil et" IsChecked="True" Foreground="#334155"/>
                </StackPanel>

                <StackPanel Grid.Column="5" VerticalAlignment="Bottom" Margin="0,0,12,6">
                    <CheckBox
                        x:Name="chkStrongUsdOnly"
                        Content="Yalnızca USD güçlü bilanço"
                        IsChecked="False"
                        Foreground="#334155"
                        ToolTip="Son çeyrek USD kârı pozitif, son 5 çeyreğin en az 4'ü kârlı, USD kâr yıllık en az %15 büyümüş veya zarardan kâra dönmüş ve USD ciro yıllık negatif değil."/>
                </StackPanel>

                <Button x:Name="btnClearFilters" Grid.Column="6" Content="Filtreleri Temizle" Style="{StaticResource SecondaryButton}" VerticalAlignment="Bottom"/>
            </Grid>
        </Border>

        <TabControl Grid.Row="2" Margin="14" x:Name="tabMain">
            <TabItem Header="Hisse Tarayıcı">
                <Grid Margin="0,8,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="600"/>
                    </Grid.ColumnDefinitions>

                    <Border Grid.Column="0" Background="White" BorderBrush="#E2E8F0" BorderThickness="1" CornerRadius="4" Margin="0,0,12,0">
                <DataGrid
                    x:Name="gridStocks"
                    AutoGenerateColumns="False"
                    IsReadOnly="True"
                    SelectionMode="Single"
                    SelectionUnit="FullRow"
                    HeadersVisibility="Column"
                    GridLinesVisibility="Horizontal"
                    HorizontalGridLinesBrush="#EEF2F7"
                    BorderThickness="0"
                    RowHeight="30"
                    ColumnHeaderHeight="34"
                    AlternatingRowBackground="#F8FAFC"
                    EnableRowVirtualization="True"
                    EnableColumnVirtualization="True"
                    CanUserReorderColumns="True"
                    CanUserResizeColumns="True"
                    CanUserSortColumns="True">
                    <DataGrid.RowStyle>
                        <Style TargetType="DataGridRow">
                            <Setter Property="ToolTip" Value="{Binding RiskFlags}"/>
                            <Style.Triggers>
                                <DataTrigger Binding="{Binding Signal}" Value="Güçlü İzle">
                                    <Setter Property="Background" Value="#ECFDF5"/>
                                </DataTrigger>
                                <DataTrigger Binding="{Binding Signal}" Value="İzle">
                                    <Setter Property="Background" Value="#F0FDF4"/>
                                </DataTrigger>
                                <DataTrigger Binding="{Binding Signal}" Value="Temkinli">
                                    <Setter Property="Background" Value="#FFF7ED"/>
                                </DataTrigger>
                                <DataTrigger Binding="{Binding Signal}" Value="Zayıf">
                                    <Setter Property="Background" Value="#FEF2F2"/>
                                </DataTrigger>
                            </Style.Triggers>
                        </Style>
                    </DataGrid.RowStyle>
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="Skor" Binding="{Binding Score, StringFormat={}{0:N1}}" Width="58"/>
                        <DataGridTextColumn Header="Görüş" Binding="{Binding Signal}" Width="82"/>
                        <DataGridTextColumn Header="Teyit" Binding="{Binding ConfirmationLabel}" Width="132"/>
                        <DataGridTextColumn Header="Sembol" Binding="{Binding Symbol}" Width="78"/>
                        <DataGridTextColumn Header="Şirket" Binding="{Binding Company}" Width="2*"/>
                        <DataGridTextColumn Header="USD Bilanço" Binding="{Binding StrongUsdEarningsLabel}" Width="88"/>
                        <DataGridTextColumn Header="Son Kâr (Mr TL)" Binding="{Binding LatestNetIncomeTRYBn, StringFormat={}{0:N2}}" Width="104"/>
                        <DataGridTextColumn Header="Son Kâr (Mn $)" Binding="{Binding LatestNetIncomeUSDMn, StringFormat={}{0:N1}}" Width="102"/>
                        <DataGridTextColumn Header="Kâr USD Y/Y %" Binding="{Binding NetIncomeUsdYoYPct, StringFormat={}{0:N1}}" Width="100"/>
                        <DataGridTextColumn Header="FAVÖK USD Y/Y %" Binding="{Binding EbitdaUsdYoYPct, StringFormat={}{0:N1}}" Width="112"/>
                        <DataGridTextColumn Header="FD/FAVÖK" Binding="{Binding EvEbitda, StringFormat={}{0:N2}}" Width="78"/>
                        <DataGridTextColumn Header="Makro/Sektör" Binding="{Binding MacroSectorScore, StringFormat={}{0:N1}}" Width="96"/>
                        <DataGridTextColumn Header="BIST Alfa 1Y" Binding="{Binding StockVsBist1YPct, StringFormat={}{0:N1}}" Width="90"/>
                        <DataGridTextColumn Header="Sektör Rot." Binding="{Binding SectorRotationLabel}" Width="92"/>
                        <DataGridTextColumn Header="Son" Binding="{Binding Price, StringFormat={}{0:N2}}" Width="76"/>
                        <DataGridTextColumn Header="Gün %" Binding="{Binding ChangePct, StringFormat={}{0:N2}}" Width="68"/>
                        <DataGridTextColumn Header="Piyasa Değ. (Mr TL)" Binding="{Binding MarketCapBn, StringFormat={}{0:N1}}" Width="118"/>
                        <DataGridTextColumn Header="Hacim (Lot)" Binding="{Binding Volume, StringFormat={}{0:N0}}" Width="105"/>
                        <DataGridTextColumn Header="Göreli Hacim" Binding="{Binding RelativeVolume, StringFormat={}{0:N2}}" Width="92"/>
                        <DataGridTextColumn Header="F/K" Binding="{Binding PE, StringFormat={}{0:N2}}" Width="64"/>
                        <DataGridTextColumn Header="PD/DD" Binding="{Binding PB, StringFormat={}{0:N2}}" Width="68"/>
                        <DataGridTextColumn Header="ROE %" Binding="{Binding ROE, StringFormat={}{0:N2}}" Width="72"/>
                        <DataGridTextColumn Header="RSI" Binding="{Binding RSI, StringFormat={}{0:N1}}" Width="62"/>
                        <DataGridTextColumn Header="1 Ay %" Binding="{Binding PerfMonth, StringFormat={}{0:N2}}" Width="72"/>
                        <DataGridTextColumn Header="Risk" Binding="{Binding RiskLevel}" Width="66"/>
                        <DataGridTextColumn Header="Sektör" Binding="{Binding SectorTR}" Width="150"/>
                        <DataGridTextColumn Header="Alt Sektör (TV)" Binding="{Binding Industry}" Width="165"/>
                    </DataGrid.Columns>
                </DataGrid>
                    </Border>

                    <Border Grid.Column="1" Background="White" BorderBrush="#E2E8F0" BorderThickness="1" CornerRadius="4">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="18">
                        <TextBlock x:Name="txtDetailSymbol" Text="Hisse seçin" Foreground="#0F172A" FontSize="24" FontWeight="SemiBold"/>
                        <TextBlock x:Name="txtDetailCompany" Text="Puanın neden oluştuğunu burada görebilirsiniz." Foreground="#64748B" FontSize="12" TextWrapping="Wrap" Margin="0,4,0,0"/>

                        <UniformGrid Columns="2" Margin="0,16,0,0">
                            <Border Background="#F8FAFC" BorderBrush="#E2E8F0" BorderThickness="1" Padding="10" Margin="0,0,5,5">
                                <StackPanel>
                                    <TextBlock Text="Son Fiyat" Style="{StaticResource MetricLabel}"/>
                                    <TextBlock x:Name="txtDetailPrice" Text="-" Style="{StaticResource MetricValue}"/>
                                </StackPanel>
                            </Border>
                            <Border Background="#F8FAFC" BorderBrush="#E2E8F0" BorderThickness="1" Padding="10" Margin="5,0,0,5">
                                <StackPanel>
                                    <TextBlock Text="Günlük Değişim" Style="{StaticResource MetricLabel}"/>
                                    <TextBlock x:Name="txtDetailChange" Text="-" Style="{StaticResource MetricValue}"/>
                                </StackPanel>
                            </Border>
                            <Border Background="#F8FAFC" BorderBrush="#E2E8F0" BorderThickness="1" Padding="10" Margin="0,5,5,0">
                                <StackPanel>
                                    <TextBlock Text="Piyasa Değeri" Style="{StaticResource MetricLabel}"/>
                                    <TextBlock x:Name="txtDetailMarketCap" Text="-" Style="{StaticResource MetricValue}"/>
                                </StackPanel>
                            </Border>
                            <Border Background="#F8FAFC" BorderBrush="#E2E8F0" BorderThickness="1" Padding="10" Margin="5,5,0,0">
                                <StackPanel>
                                    <TextBlock Text="Risk Seviyesi" Style="{StaticResource MetricLabel}"/>
                                    <TextBlock x:Name="txtDetailRisk" Text="-" Style="{StaticResource MetricValue}"/>
                                </StackPanel>
                            </Border>
                            <Border Background="#F8FAFC" BorderBrush="#E2E8F0" BorderThickness="1" Padding="10" Margin="0,5,5,0">
                                <StackPanel>
                                    <TextBlock Text="Son Çeyrek Kârı" Style="{StaticResource MetricLabel}"/>
                                    <TextBlock x:Name="txtDetailProfitTL" Text="-" Style="{StaticResource MetricValue}"/>
                                </StackPanel>
                            </Border>
                            <Border Background="#F8FAFC" BorderBrush="#E2E8F0" BorderThickness="1" Padding="10" Margin="5,5,0,0">
                                <StackPanel>
                                    <TextBlock Text="Son Çeyrek Kârı USD" Style="{StaticResource MetricLabel}"/>
                                    <TextBlock x:Name="txtDetailProfitUSD" Text="-" Style="{StaticResource MetricValue}"/>
                                </StackPanel>
                            </Border>
                            <Border Background="#F8FAFC" BorderBrush="#E2E8F0" BorderThickness="1" Padding="10" Margin="0,5,5,0">
                                <StackPanel>
                                    <TextBlock Text="Son Çeyrek FAVÖK" Style="{StaticResource MetricLabel}"/>
                                    <TextBlock x:Name="txtDetailEbitdaTL" Text="-" Style="{StaticResource MetricValue}"/>
                                </StackPanel>
                            </Border>
                            <Border Background="#F8FAFC" BorderBrush="#E2E8F0" BorderThickness="1" Padding="10" Margin="5,5,0,0">
                                <StackPanel>
                                    <TextBlock Text="FAVÖK USD / FD-FAVÖK" Style="{StaticResource MetricLabel}"/>
                                    <TextBlock x:Name="txtDetailEbitdaUSD" Text="-" Style="{StaticResource MetricValue}"/>
                                </StackPanel>
                            </Border>
                            <Border Background="#F8FAFC" BorderBrush="#E2E8F0" BorderThickness="1" Padding="10" Margin="0,5,5,0">
                                <StackPanel>
                                    <TextBlock Text="Son Finansal Dönem" Style="{StaticResource MetricLabel}"/>
                                    <TextBlock x:Name="txtDetailQuarter" Text="-" Style="{StaticResource MetricValue}"/>
                                </StackPanel>
                            </Border>
                            <Border Background="#F8FAFC" BorderBrush="#E2E8F0" BorderThickness="1" Padding="10" Margin="5,5,0,0">
                                <StackPanel>
                                    <TextBlock Text="USD Bilanço" Style="{StaticResource MetricLabel}"/>
                                    <TextBlock x:Name="txtDetailUsdStrength" Text="-" Style="{StaticResource MetricValue}"/>
                                </StackPanel>
                            </Border>
                            <Border Background="#F8FAFC" BorderBrush="#E2E8F0" BorderThickness="1" Padding="10" Margin="0,5,5,0">
                                <StackPanel>
                                    <TextBlock Text="Sektör" Style="{StaticResource MetricLabel}"/>
                                    <TextBlock x:Name="txtDetailSector" Text="-" Style="{StaticResource MetricValue}" FontSize="14" TextWrapping="Wrap"/>
                                </StackPanel>
                            </Border>
                            <Border Background="#F8FAFC" BorderBrush="#E2E8F0" BorderThickness="1" Padding="10" Margin="5,5,0,0">
                                <StackPanel>
                                    <TextBlock Text="Alt Sektör (TradingView)" Style="{StaticResource MetricLabel}"/>
                                    <TextBlock x:Name="txtDetailIndustry" Text="-" Style="{StaticResource MetricValue}" FontSize="14" TextWrapping="Wrap"/>
                                </StackPanel>
                            </Border>
                        </UniformGrid>

                        <TextBlock Text="Puan Bileşenleri" Style="{StaticResource SectionTitle}"/>

                        <Grid Margin="0,2,0,6">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="75"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="38"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="Trend" Foreground="#475569" VerticalAlignment="Center"/>
                            <ProgressBar x:Name="pbTrend" Grid.Column="1" Height="8" Maximum="100" Value="0" Foreground="#2563EB"/>
                            <TextBlock x:Name="txtTrendScore" Grid.Column="2" Text="-" Foreground="#334155" HorizontalAlignment="Right"/>
                        </Grid>
                        <Grid Margin="0,2,0,6">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="75"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="38"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="Değer" Foreground="#475569" VerticalAlignment="Center"/>
                            <ProgressBar x:Name="pbValue" Grid.Column="1" Height="8" Maximum="100" Value="0" Foreground="#0EA5E9"/>
                            <TextBlock x:Name="txtValueScore" Grid.Column="2" Text="-" Foreground="#334155" HorizontalAlignment="Right"/>
                        </Grid>
                        <Grid Margin="0,2,0,6">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="75"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="38"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="Kalite" Foreground="#475569" VerticalAlignment="Center"/>
                            <ProgressBar x:Name="pbQuality" Grid.Column="1" Height="8" Maximum="100" Value="0" Foreground="#10B981"/>
                            <TextBlock x:Name="txtQualityScore" Grid.Column="2" Text="-" Foreground="#334155" HorizontalAlignment="Right"/>
                        </Grid>
                        <Grid Margin="0,2,0,6">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="75"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="38"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="Bilanço" Foreground="#475569" VerticalAlignment="Center"/>
                            <ProgressBar x:Name="pbEarnings" Grid.Column="1" Height="8" Maximum="100" Value="0" Foreground="#14B8A6"/>
                            <TextBlock x:Name="txtEarningsScore" Grid.Column="2" Text="-" Foreground="#334155" HorizontalAlignment="Right"/>
                        </Grid>
                        <Grid Margin="0,2,0,6">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="75"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="38"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="Momentum" Foreground="#475569" VerticalAlignment="Center"/>
                            <ProgressBar x:Name="pbMomentum" Grid.Column="1" Height="8" Maximum="100" Value="0" Foreground="#8B5CF6"/>
                            <TextBlock x:Name="txtMomentumScore" Grid.Column="2" Text="-" Foreground="#334155" HorizontalAlignment="Right"/>
                        </Grid>
                        <Grid Margin="0,2,0,6">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="75"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="38"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="Likidite" Foreground="#475569" VerticalAlignment="Center"/>
                            <ProgressBar x:Name="pbLiquidity" Grid.Column="1" Height="8" Maximum="100" Value="0" Foreground="#F59E0B"/>
                            <TextBlock x:Name="txtLiquidityScore" Grid.Column="2" Text="-" Foreground="#334155" HorizontalAlignment="Right"/>
                        </Grid>
                        <Grid Margin="0,2,0,6">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="75"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="38"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="Makro/Sek." Foreground="#475569" VerticalAlignment="Center"/>
                            <ProgressBar x:Name="pbMacroSector" Grid.Column="1" Height="8" Maximum="100" Value="0" Foreground="#6366F1"/>
                            <TextBlock x:Name="txtMacroSectorScore" Grid.Column="2" Text="-" Foreground="#334155" HorizontalAlignment="Right"/>
                        </Grid>

                        <TextBlock Text="Son 5 Çeyrek Kârlılık Grafikleri" Style="{StaticResource SectionTitle}"/>
                        <TextBlock Text="TL ve USD farklı ölçeklerde olduğu için ayrı bar grafiklerde gösterilir. Sıfır çizgisinin altındaki barlar zararı ifade eder." Foreground="#64748B" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,6"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Border Grid.Column="0" Background="#F8FAFC" BorderBrush="#E2E8F0" BorderThickness="1" Padding="6" Margin="0,0,5,0">
                                <StackPanel>
                                    <TextBlock Text="Net Kâr (Milyar TL)" Foreground="#334155" FontSize="12" FontWeight="SemiBold" HorizontalAlignment="Center"/>
                                    <Canvas x:Name="canvasProfitTL" Width="255" Height="180" Background="#F8FAFC"/>
                                </StackPanel>
                            </Border>
                            <Border Grid.Column="1" Background="#F8FAFC" BorderBrush="#E2E8F0" BorderThickness="1" Padding="6" Margin="5,0,0,0">
                                <StackPanel>
                                    <TextBlock Text="Net Kâr (Milyon USD)" Foreground="#334155" FontSize="12" FontWeight="SemiBold" HorizontalAlignment="Center"/>
                                    <Canvas x:Name="canvasProfitUSD" Width="255" Height="180" Background="#F8FAFC"/>
                                </StackPanel>
                            </Border>
                        </Grid>

                        <TextBlock Text="Son Çeyrek Kâr Kaynağı Mutabakatı" Style="{StaticResource SectionTitle}"/>
                        <TextBlock Text="Faaliyet kârı ile net kâr arasındaki fark; finansman, vergi, iştirak, değerleme ve diğer faaliyet dışı etkileri birlikte içerebilir." Foreground="#64748B" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,6"/>
                        <Border Background="#F8FAFC" BorderBrush="#E2E8F0" BorderThickness="1" Padding="8">
                            <Canvas x:Name="canvasProfitSource" Width="530" Height="205" Background="#F8FAFC"/>
                        </Border>
                        <TextBlock x:Name="txtProfitSourceNote" Text="Bir hisse seçildiğinde kâr kaynağı açıklaması gösterilir." Foreground="#64748B" FontSize="11" TextWrapping="Wrap" Margin="0,6,0,0"/>

                        <TextBlock Text="Son 5 Çeyrek Finansallar" Style="{StaticResource SectionTitle}"/>
                        <TextBlock Text="Net kâr TL ve USD olarak gösterilir. USD dönüşümü TCMB çeyrek sonu döviz alış kuruyla yapılır." Foreground="#64748B" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,6"/>
                        <DataGrid
                            x:Name="gridQuarterly"
                            Height="190"
                            AutoGenerateColumns="False"
                            IsReadOnly="True"
                            HeadersVisibility="Column"
                            GridLinesVisibility="Horizontal"
                            HorizontalGridLinesBrush="#EEF2F7"
                            BorderBrush="#E2E8F0"
                            BorderThickness="1"
                            RowHeight="27"
                            ColumnHeaderHeight="30"
                            CanUserAddRows="False"
                            CanUserDeleteRows="False"
                            CanUserReorderColumns="False">
                            <DataGrid.Columns>
                                <DataGridTextColumn Header="Dönem" Binding="{Binding Period}" Width="70"/>
                                <DataGridTextColumn Header="Kâr Mr TL" Binding="{Binding NetIncomeTRYBn, StringFormat={}{0:N2}}" Width="78"/>
                                <DataGridTextColumn Header="Kâr Mn $" Binding="{Binding NetIncomeUSDMn, StringFormat={}{0:N1}}" Width="76"/>
                                <DataGridTextColumn Header="FAVÖK Mr TL" Binding="{Binding EbitdaTRYBn, StringFormat={}{0:N2}}" Width="88"/>
                                <DataGridTextColumn Header="FAVÖK Mn $" Binding="{Binding EbitdaUSDMn, StringFormat={}{0:N1}}" Width="84"/>
                                <DataGridTextColumn Header="Ciro Mr TL" Binding="{Binding RevenueTRYBn, StringFormat={}{0:N1}}" Width="82"/>
                                <DataGridTextColumn Header="Varlık Mr TL" Binding="{Binding TotalAssetsTRYBn, StringFormat={}{0:N1}}" Width="90"/>
                                <DataGridTextColumn Header="Borç Mr TL" Binding="{Binding TotalDebtTRYBn, StringFormat={}{0:N1}}" Width="84"/>
                                <DataGridTextColumn Header="SNA Mr TL" Binding="{Binding FreeCashFlowTRYBn, StringFormat={}{0:N1}}" Width="82"/>
                            </DataGrid.Columns>
                        </DataGrid>

                        <TextBlock Text="Tarama Açıklaması" Style="{StaticResource SectionTitle}"/>
                        <TextBlock x:Name="txtExplanation" Text="Canlı tarama tamamlandığında bir hisse seçin." Foreground="#475569" FontSize="12" TextWrapping="Wrap" LineHeight="18"/>

                        <Border Background="#FFFBEB" BorderBrush="#FDE68A" BorderThickness="1" Padding="10" Margin="0,18,0,0">
                            <TextBlock Text="Bu uygulama yatırım tavsiyesi değildir. Veriler gecikmeli, eksik veya hatalı olabilir; işlem öncesinde KAP bildirimleri ve lisanslı kaynaklarla doğrulayın." Foreground="#92400E" FontSize="11" TextWrapping="Wrap"/>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
                    </Border>
                </Grid>
            </TabItem>

            <TabItem Header="Anlık Giriş Fırsatı">
                <Grid Margin="0,8,0,0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Border Background="White" BorderBrush="#E2E8F0" BorderThickness="1" CornerRadius="4" Padding="16" Margin="0,0,0,10">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel>
                                <TextBlock Text="Anlık Giriş Fırsatı" Foreground="#0F172A" FontSize="22" FontWeight="SemiBold"/>
                                <TextBlock Text="Temeli iyi olan hisselerde skor 85+, MACD yeni sıfır kesişimi veya pozitif ivme + 52H %20-50 bandı şartını sağlayan anlık alış adaylarını gösterir; sayı sabit değildir." Foreground="#64748B" FontSize="12" TextWrapping="Wrap" Margin="0,4,0,0"/>
                            </StackPanel>
                            <Button x:Name="btnRefreshEntryOpportunities" Grid.Column="1" Content="Radarı Yenile" Style="{StaticResource SecondaryButton}" VerticalAlignment="Center" Margin="14,0,0,0"/>
                        </Grid>
                    </Border>

                    <Border Grid.Row="1" Background="White" BorderBrush="#E2E8F0" BorderThickness="1" CornerRadius="4">
                        <DataGrid
                            x:Name="gridEntryOpportunities"
                            AutoGenerateColumns="False"
                            IsReadOnly="True"
                            SelectionMode="Single"
                            SelectionUnit="FullRow"
                            HeadersVisibility="Column"
                            GridLinesVisibility="Horizontal"
                            HorizontalGridLinesBrush="#EEF2F7"
                            BorderThickness="0"
                            RowHeight="34"
                            ColumnHeaderHeight="34"
                            AlternatingRowBackground="#F8FAFC"
                            EnableRowVirtualization="True"
                            EnableColumnVirtualization="True"
                            CanUserReorderColumns="True"
                            CanUserResizeColumns="True"
                            CanUserSortColumns="True">
                            <DataGrid.Columns>
                                <DataGridTextColumn Header="Sıra" Binding="{Binding Rank}" Width="46"/>
                                <DataGridTextColumn Header="Giriş Skoru" Binding="{Binding EntryOpportunityScore, StringFormat={}{0:N1}}" Width="86"/>
                                <DataGridTextColumn Header="Sembol" Binding="{Binding Symbol}" Width="78"/>
                                <DataGridTextColumn Header="Şirket" Binding="{Binding Company}" Width="180"/>
                                <DataGridTextColumn Header="Sektör" Binding="{Binding SectorTR}" Width="140"/>
                                <DataGridTextColumn Header="Fiyat" Binding="{Binding Price, StringFormat={}{0:N2}}" Width="76"/>
                                <DataGridTextColumn Header="Haftalık Etiket" Binding="{Binding WeeklyHistogramLabel}" Width="128"/>
                                <DataGridTextColumn Header="Üst Üste Hist" Binding="{Binding WeeklyHistogramRisingWeeks}" Width="92"/>
                                <DataGridTextColumn Header="8 Haftada Artış" Binding="{Binding WeeklyHistogramIncreaseCount}" Width="98"/>
                                <DataGridTextColumn Header="Son Hist" Binding="{Binding LastWeeklyHistogram, StringFormat={}{0:N2}}" Width="74"/>
                                <DataGridTextColumn Header="Önceki Hist" Binding="{Binding PreviousWeeklyHistogram, StringFormat={}{0:N2}}" Width="82"/>
                                <DataGridTextColumn Header="RSI" Binding="{Binding RSI, StringFormat={}{0:N1}}" Width="62"/>
                                <DataGridTextColumn Header="Hacim" Binding="{Binding RelativeVolume, StringFormat={}{0:N2}x}" Width="70"/>
                                <DataGridTextColumn Header="FD/FAVÖK" Binding="{Binding EvEbitda, StringFormat={}{0:N2}}" Width="78"/>
                                <DataGridTextColumn Header="52H Konum" Binding="{Binding Range52PositionPct, StringFormat={}{0:N1}%}" Width="82"/>
                                <DataGridTextColumn Header="52H Bant" Binding="{Binding Range52Bucket}" Width="112"/>
                                <DataGridTextColumn Header="BIST 4H" Binding="{Binding MarketRegimeChangePct, StringFormat={}{0:N1}%}" Width="74"/>
                                <DataGridTextColumn Header="Makro/Sektör" Binding="{Binding MacroSectorScore, StringFormat={}{0:N1}}" Width="96"/>
                                <DataGridTextColumn Header="Neden Şimdi İzlenir" Binding="{Binding Reason}" Width="3*"/>
                            </DataGrid.Columns>
                        </DataGrid>
                    </Border>

                    <Border Grid.Row="2" Background="#FFFBEB" BorderBrush="#FDE68A" BorderThickness="1" Padding="10" Margin="0,10,0,0">
                        <TextBlock Text="Bu sekme emir önerisi değildir. Haftalık MACD histogramı güncel haftada değişebilir; adaylar işlem öncesi grafik, KAP, haber akışı ve likiditeyle ayrıca doğrulanmalıdır." Foreground="#92400E" FontSize="11" TextWrapping="Wrap"/>
                    </Border>
                </Grid>
            </TabItem>

            <TabItem Header="Sektörel Döngüler">
                <Border Background="White" BorderBrush="#E2E8F0" BorderThickness="1" CornerRadius="4" Margin="0,8,0,0">
                    <Grid Margin="18">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <StackPanel>
                            <TextBlock Text="Sektörel Döngü Rehberi" Foreground="#0F172A" FontSize="22" FontWeight="SemiBold"/>
                            <TextBlock Text="Sektör hisselerinin hangi beklentilerle hareketlenme eğiliminde olduğunu, hangi koşullarda baskı görebileceğini ve hangi göstergelerin izlenebileceğini özetler." Foreground="#64748B" FontSize="12" TextWrapping="Wrap" Margin="0,4,0,14"/>
                        </StackPanel>

                        <Grid Grid.Row="1">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="300"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <ListBox
                                x:Name="listSectorCycles"
                                DisplayMemberPath="SectorTR"
                                BorderBrush="#E2E8F0"
                                BorderThickness="1"
                                Background="#F8FAFC"
                                Padding="4"
                                Margin="0,0,14,0"/>
                            <Border Grid.Column="1" BorderBrush="#E2E8F0" BorderThickness="1" Padding="18">
                                <ScrollViewer VerticalScrollBarVisibility="Auto">
                                    <StackPanel>
                                        <TextBlock x:Name="txtSectorGuideTitle" Text="Bir sektör seçin" Foreground="#0F172A" FontSize="20" FontWeight="SemiBold"/>
                                        <TextBlock x:Name="txtSectorGuideCycle" Text="" Foreground="#2563EB" FontSize="12" FontWeight="SemiBold" Margin="0,5,0,12"/>
                                        <TextBlock x:Name="txtSectorGuideSummary" Text="" Foreground="#475569" FontSize="12" TextWrapping="Wrap" LineHeight="18"/>

                                        <TextBlock Text="Hareketi Destekleyen Koşullar" Style="{StaticResource SectionTitle}"/>
                                        <TextBlock x:Name="txtSectorGuidePositive" Text="" Foreground="#475569" FontSize="12" TextWrapping="Wrap" LineHeight="18"/>

                                        <TextBlock Text="Baskı Oluşturabilecek Koşullar" Style="{StaticResource SectionTitle}"/>
                                        <TextBlock x:Name="txtSectorGuideNegative" Text="" Foreground="#475569" FontSize="12" TextWrapping="Wrap" LineHeight="18"/>

                                        <TextBlock Text="İzlenecek Göstergeler" Style="{StaticResource SectionTitle}"/>
                                        <TextBlock x:Name="txtSectorGuideIndicators" Text="" Foreground="#475569" FontSize="12" TextWrapping="Wrap" LineHeight="18"/>

                                        <TextBlock Text="Yorumlama Notu" Style="{StaticResource SectionTitle}"/>
                                        <TextBlock x:Name="txtSectorGuideNote" Text="" Foreground="#475569" FontSize="12" TextWrapping="Wrap" LineHeight="18"/>
                                    </StackPanel>
                                </ScrollViewer>
                            </Border>
                        </Grid>

                        <Border Grid.Row="2" Background="#FFFBEB" BorderBrush="#FDE68A" BorderThickness="1" Padding="10" Margin="0,14,0,0">
                            <TextBlock Text="Sektörel döngüler kesin zamanlama sinyali değildir. Hisse fiyatları çoğu zaman gerçekleşen veriden önce beklentiyi fiyatlar; şirketin bilançosu, değerlemesi, yönetimi ve özel haber akışı ayrıca incelenmelidir." Foreground="#92400E" FontSize="11" TextWrapping="Wrap"/>
                        </Border>
                    </Grid>
                </Border>
            </TabItem>

            <TabItem Header="Model Portföyler">
                <Grid Margin="0,8,0,0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Border Background="White" BorderBrush="#E2E8F0" BorderThickness="1" CornerRadius="4" Padding="16" Margin="0,0,0,10">
                        <StackPanel>
                            <TextBlock Text="Aylık Eşit Ağırlıklı Model Portföyler" Foreground="#0F172A" FontSize="22" FontWeight="SemiBold"/>
                            <TextBlock Text="Dört stratejinin her biri 100.000 TL teorik başlangıç sermayesiyle, 5 hisse ve hisse başına %20 ağırlıkla izlenir. İşlemler yalnızca ilk kurulumda ve ayın son BIST işlem günü kapanışından sonraki canlı taramada yapılır." Foreground="#64748B" FontSize="12" TextWrapping="Wrap" Margin="0,4,0,0"/>
                        </StackPanel>
                    </Border>

                    <TabControl x:Name="tabModelPortfolios" Grid.Row="1"/>

                    <Border Grid.Row="2" Background="#FFFBEB" BorderBrush="#FDE68A" BorderThickness="1" Padding="10" Margin="0,10,0,0">
                        <TextBlock Text="Model portföyler gerçek emir değildir ve yatırım tavsiyesi vermez. Tam %20 ağırlık için teorik kesirli adet kullanılır; komisyon, vergi, fiyat kayması, temettü ve sermaye hareketleri otomatik hesaba katılmaz. Uygulama ay sonu kapalıysa işlem ilk sonraki canlı taramada gecikmeli yapılır." Foreground="#92400E" FontSize="11" TextWrapping="Wrap"/>
                    </Border>
                </Grid>
            </TabItem>
        </TabControl>

        <Border Grid.Row="3" Background="#FFFFFF" BorderBrush="#E2E8F0" BorderThickness="0,1,0,0" Padding="14,8">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="txtStatus" Text="Başlatılıyor..." Foreground="#475569" FontSize="11"/>
                <TextBlock x:Name="txtSource" Grid.Column="1" Text="Kaynak: TradingView Türkiye tarayıcısı + TCMB kur arşivi + Yahoo haftalık fiyat" Foreground="#94A3B8" FontSize="11"/>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

$xml = [xml]$xaml
$reader = New-Object System.Xml.XmlNodeReader $xml
$window = [Windows.Markup.XamlReader]::Load($reader)

function Get-Control {
    param([string]$Name)
    return $window.FindName($Name)
}

$txtBusy = Get-Control 'txtBusy'
$btnExport = Get-Control 'btnExport'
$btnOpenChart = Get-Control 'btnOpenChart'
$btnScan = Get-Control 'btnScan'
$txtSearch = Get-Control 'txtSearch'
$cmbStrategy = Get-Control 'cmbStrategy'
$cmbMarketCap = Get-Control 'cmbMarketCap'
$sldMinScore = Get-Control 'sldMinScore'
$txtMinScore = Get-Control 'txtMinScore'
$chkIncludeHighRisk = Get-Control 'chkIncludeHighRisk'
$chkStrongUsdOnly = Get-Control 'chkStrongUsdOnly'
$btnClearFilters = Get-Control 'btnClearFilters'
$gridStocks = Get-Control 'gridStocks'
$gridEntryOpportunities = Get-Control 'gridEntryOpportunities'
$btnRefreshEntryOpportunities = Get-Control 'btnRefreshEntryOpportunities'
$gridQuarterly = Get-Control 'gridQuarterly'
$txtDetailSymbol = Get-Control 'txtDetailSymbol'
$txtDetailCompany = Get-Control 'txtDetailCompany'
$txtDetailPrice = Get-Control 'txtDetailPrice'
$txtDetailChange = Get-Control 'txtDetailChange'
$txtDetailMarketCap = Get-Control 'txtDetailMarketCap'
$txtDetailRisk = Get-Control 'txtDetailRisk'
$txtDetailProfitTL = Get-Control 'txtDetailProfitTL'
$txtDetailProfitUSD = Get-Control 'txtDetailProfitUSD'
$txtDetailEbitdaTL = Get-Control 'txtDetailEbitdaTL'
$txtDetailEbitdaUSD = Get-Control 'txtDetailEbitdaUSD'
$txtDetailQuarter = Get-Control 'txtDetailQuarter'
$txtDetailUsdStrength = Get-Control 'txtDetailUsdStrength'
$txtDetailSector = Get-Control 'txtDetailSector'
$txtDetailIndustry = Get-Control 'txtDetailIndustry'
$pbTrend = Get-Control 'pbTrend'
$pbValue = Get-Control 'pbValue'
$pbQuality = Get-Control 'pbQuality'
$pbEarnings = Get-Control 'pbEarnings'
$pbMomentum = Get-Control 'pbMomentum'
$pbLiquidity = Get-Control 'pbLiquidity'
$pbMacroSector = Get-Control 'pbMacroSector'
$txtTrendScore = Get-Control 'txtTrendScore'
$txtValueScore = Get-Control 'txtValueScore'
$txtQualityScore = Get-Control 'txtQualityScore'
$txtEarningsScore = Get-Control 'txtEarningsScore'
$txtMomentumScore = Get-Control 'txtMomentumScore'
$txtLiquidityScore = Get-Control 'txtLiquidityScore'
$txtMacroSectorScore = Get-Control 'txtMacroSectorScore'
$canvasProfitTL = Get-Control 'canvasProfitTL'
$canvasProfitUSD = Get-Control 'canvasProfitUSD'
$canvasProfitSource = Get-Control 'canvasProfitSource'
$txtProfitSourceNote = Get-Control 'txtProfitSourceNote'
$txtExplanation = Get-Control 'txtExplanation'
$txtStatus = Get-Control 'txtStatus'
$listSectorCycles = Get-Control 'listSectorCycles'
$txtSectorGuideTitle = Get-Control 'txtSectorGuideTitle'
$txtSectorGuideCycle = Get-Control 'txtSectorGuideCycle'
$txtSectorGuideSummary = Get-Control 'txtSectorGuideSummary'
$txtSectorGuidePositive = Get-Control 'txtSectorGuidePositive'
$txtSectorGuideNegative = Get-Control 'txtSectorGuideNegative'
$txtSectorGuideIndicators = Get-Control 'txtSectorGuideIndicators'
$txtSectorGuideNote = Get-Control 'txtSectorGuideNote'
$tabModelPortfolios = Get-Control 'tabModelPortfolios'

$script:allStocks = @()
$script:scoredStocks = @()
$script:filteredStocks = @()
$script:entryOpportunities = @()
$script:modelPortfolioSet = $null
$script:portfolioUi = @{}
$script:scanJob = $null
$script:entryOpportunityJob = $null
$script:lastUpdated = $null
$script:loadedFromCache = $false
$script:cachePath = Join-Path $PSScriptRoot 'data\last_scan.json'
$script:portfolioPath = Join-Path $PSScriptRoot 'data\model_portfolios.json'
$script:marketCapFilters = @(0, 1000000000, 5000000000, 10000000000, 50000000000)
$script:trCulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
$script:positiveBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#059669')
$script:negativeBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#DC2626')
$script:neutralBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#0F172A')
$script:strongBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#0F766E')
$script:sectorGuides = @(
    [pscustomobject][ordered]@{
        SectorTR = 'Finans (Bankacılık dahil)'
        SectorEN = 'Finance'
        Cycle = 'Faiz, risk primi, regülasyon ve yabancı sermaye döngüsü'
        Summary = 'Banka ve finans hisseleri; fonlama maliyeti, net faiz marjı, kredi büyümesi, aktif kalitesi ve sermaye yeterliliği beklentileriyle hareket eder. Fiyatlar çoğu zaman bilanço iyileşmesi açıklanmadan önce faiz, kur ve regülasyon patikasındaki değişimi fiyatlamaya başlar.'
        Positive = 'Yabancı yatırımcı girişinin güçlenmesi; ülke risk priminin (CDS) gerilemesi; TL kurunda öngörülebilirlik; regülasyonların sadeleşmesi; mevduat maliyetinin rahatlayacağı ve net faiz marjının toparlanacağı beklentisi; takipteki alacakların sınırlı kalması; güçlü ücret ve komisyon gelirleri.'
        Negative = 'Ani kur şoku; CDS yükselişi; mevduat maliyetinin kredi getirilerinden hızlı artması; kredi kalitesinde bozulma; takipteki alacak ve karşılık giderlerinin yükselmesi; sermaye yeterliliğini zorlayan hızlı büyüme; kârlılığı sınırlayan yeni düzenlemeler.'
        Indicators = 'TCMB faiz kararları ve metinleri; BDDK haftalık bankacılık verileri; 5 yıllık CDS; yabancı takas oranı ve net hisse/tahvil alımları; mevduat-kredi faizleri; kredi büyümesi; takipteki alacak oranı; sermaye yeterlilik oranı; bankaların net faiz marjı rehberliği.'
        Note = 'Yabancı girişi önemli bir talep göstergesidir, ancak tek başına kalıcı yükseliş garantisi değildir. En güçlü senaryo, yabancı girişinin düşen risk primi ve iyileşen banka kârlılığı beklentisiyle aynı anda görülmesidir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'İletişim'
        SectorEN = 'Communications'
        Cycle = 'Savunmacı nakit akışı, fiyatlama ve yatırım harcaması döngüsü'
        Summary = 'Telekom şirketleri tekrarlayan abonelik gelirleri nedeniyle görece savunmacıdır. Buna rağmen kârlılık; abone başı gelir artışı, fiyat tarifeleri, veri kullanımı, rekabet ve yüksek yatırım harcamalarına duyarlıdır.'
        Positive = 'Enflasyonun üzerinde fiyat artışı; abone başı gelirin yükselmesi; müşteri kaybının sınırlı kalması; veri tüketiminin büyümesi; yatırım harcamalarının gelir artışından daha yavaş seyretmesi; borçluluğun gerilemesi.'
        Negative = 'Fiyat rekabeti; yüksek lisans ve frekans bedelleri; yoğun yatırım harcaması; döviz cinsi borç baskısı; düzenleyici fiyat sınırlamaları; abone kaybı.'
        Indicators = 'Abone başı gelir, abone kayıp oranı, mobil veri kullanımı, yatırım harcaması/ciro, net borç/FAVÖK, BTK düzenlemeleri ve şirketlerin fiyatlama açıklamaları.'
        Note = 'Savunmacı sektörlerde hisse hareketi bazen hızlı büyümeden çok nakit akışı görünürlüğü ve temettü beklentisiyle gelir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Dayanıklı Tüketim'
        SectorEN = 'Consumer Durables'
        Cycle = 'Kredi, konut, ihracat ve ertelenebilir talep döngüsü'
        Summary = 'Beyaz eşya, mobilya ve benzeri dayanıklı tüketim ürünlerinde talep ertelenebilir. Bu nedenle faizler, tüketici kredisi, konut hareketliliği ve ihracat pazarları sektör üzerinde belirgindir.'
        Positive = 'Tüketici kredilerinde erişimin kolaylaşması; faizlerin düşeceği beklentisi; konut satışlarının canlanması; ihracat pazarlarında toparlanma; hammadde ve navlun maliyetlerinin gerilemesi.'
        Negative = 'Sıkı kredi koşulları; reel gelir kaybı; güçlü TL nedeniyle ihracat rekabetçiliğinin zayıflaması; çelik, plastik ve enerji maliyetlerinin yükselmesi; stok birikmesi.'
        Indicators = 'Tüketici kredileri, konut satışları, perakende satış hacmi, Avrupa PMI, ihracat adetleri, kapasite kullanım oranı ve hammadde fiyatları.'
        Note = 'Bu sektör çoğu zaman faiz indirimi gerçekleşmeden önce kredi koşullarının gevşeyeceği beklentisiyle hareketlenebilir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Dayanıksız Tüketim'
        SectorEN = 'Consumer Non-Durables'
        Cycle = 'Savunmacı talep, fiyatlama gücü ve girdi maliyeti döngüsü'
        Summary = 'Gıda, içecek ve hızlı tüketim ürünlerinde talep daha az ertelenebilir. Ana ayrım; şirketin maliyet artışını hacim kaybetmeden fiyatlara yansıtabilmesidir.'
        Positive = 'Güçlü marka ve dağıtım ağı; enflasyonun üzerinde fiyatlama; hammadde maliyetlerinde gerileme; hacimlerin korunması; ihracat pazarlarında büyüme.'
        Negative = 'Tüketicinin daha ucuz ürüne yönelmesi; tarımsal emtia ve ambalaj maliyetlerinin artması; fiyat artışlarının hacmi düşürmesi; regülasyon veya tavan fiyat riski.'
        Indicators = 'Gıda enflasyonu, satış hacmi, brüt kâr marjı, tarımsal emtia fiyatları, ambalaj ve enerji maliyetleri, modern perakende satış verileri.'
        Note = 'Savunmacı talep düşük oynaklık sağlayabilir, ancak marj daralması kârı hızla bozabilir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Tüketici Hizmetleri'
        SectorEN = 'Consumer Services'
        Cycle = 'Reel gelir, turizm ve isteğe bağlı harcama döngüsü'
        Summary = 'Eğlence, konaklama, eğitim ve benzeri hizmetlerde talep; hane gelirine, güvene, turizm akışına ve fiyatlama kabiliyetine duyarlıdır.'
        Positive = 'Reel gelir artışı; tüketici güveninde toparlanma; güçlü turizm sezonu; doluluk ve kişi başı harcamanın yükselmesi; maliyetlerin fiyatlara yansıtılması.'
        Negative = 'Hane bütçesinin zorlanması; zayıf tüketici güveni; turizm talebinde düşüş; ücret ve kira maliyetlerinin hızlı artması; fiyat artışına karşı hacim kaybı.'
        Indicators = 'Tüketici güveni, kart harcamaları, turizm ziyaretçi sayısı ve geliri, doluluk oranı, reel ücretler ve hizmet enflasyonu.'
        Note = 'İsteğe bağlı harcamalar ekonomideki yavaşlamayı erken hissedebilir; şirket bazında lokasyon ve müşteri profili önemlidir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Dağıtım Hizmetleri'
        SectorEN = 'Distribution Services'
        Cycle = 'Ticaret hacmi, stok finansmanı ve marj döngüsü'
        Summary = 'Dağıtım şirketleri yüksek ciro ve görece ince marjlarla çalışabilir. Talep hacmi, stok dönüş hızı, ticari kredi maliyeti ve tedarikçi koşulları kritik olur.'
        Positive = 'Satış hacminin büyümesi; stok devir hızının artması; tedarikçi vadelerinin iyileşmesi; finansman maliyetinin düşmesi; ürün karmasının daha yüksek marja kayması.'
        Negative = 'Stok birikmesi; yüksek işletme sermayesi ihtiyacı; pahalı kısa vadeli finansman; fiyat rekabeti; tedarik kesintileri.'
        Indicators = 'Ciro büyümesi, brüt marj, stok gün sayısı, ticari alacak ve borç günleri, işletme sermayesi, kredi faizleri ve sektör satış adetleri.'
        Note = 'Ciro büyümesi tek başına yeterli değildir; nakde dönüşmeyen büyüme finansman baskısı yaratabilir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Elektronik Teknoloji'
        SectorEN = 'Electronic Technology'
        Cycle = 'Sipariş birikimi, savunma harcaması, ihracat ve kur döngüsü'
        Summary = 'Savunma elektroniği ve yüksek teknoloji üreticilerinde uzun vadeli sipariş birikimi, teslimat takvimi, ihracat ve Ar-Ge kabiliyeti ön plandadır.'
        Positive = 'Yeni büyük sözleşmeler; sipariş birikiminin büyümesi; ihracat payının artması; savunma bütçelerinin yükselmesi; teslimatların hızlanması; döviz gelirlerinin maliyetleri karşılaması.'
        Negative = 'Proje gecikmeleri; maliyet aşımları; tahsilatın uzaması; tedarik zinciri sorunları; ihracat izinleri veya jeopolitik kısıtlar; yüksek değerleme.'
        Indicators = 'Sipariş birikimi, yeni sözleşmeler, ihracat payı, teslimat takvimi, Ar-Ge giderleri, faaliyet kâr marjı ve nakit akışı.'
        Note = 'Hisseler çoğu zaman kâr açıklamasından çok yeni sözleşme ve sipariş birikimi haberlerine erken tepki verir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Enerji Hammaddeleri'
        SectorEN = 'Energy Minerals'
        Cycle = 'Petrol, doğal gaz ve emtia fiyatı döngüsü'
        Summary = 'Enerji hammaddesi şirketlerinin gelirleri küresel petrol ve doğal gaz fiyatlarına, üretim hacmine, rezervlere ve maliyet disiplinine duyarlıdır.'
        Positive = 'Petrol veya doğal gaz fiyatlarının yükselmesi; üretim hacminin artması; yeni rezerv keşfi; düşük birim üretim maliyeti; döviz bazlı gelirlerin güçlenmesi.'
        Negative = 'Emtia fiyatlarının düşmesi; üretim kesintisi; yüksek yatırım harcaması; rezerv beklentisinin bozulması; çevresel veya düzenleyici riskler.'
        Indicators = 'Brent petrol, doğal gaz fiyatları, üretim hacmi, rezerv ömrü, birim maliyet, yatırım harcaması ve küresel enerji talebi.'
        Note = 'Emtia hisseleri bazen spot fiyattan çok gelecekteki fiyat eğrisini ve üretim artışı beklentisini fiyatlar.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Sağlık Hizmetleri'
        SectorEN = 'Health Services'
        Cycle = 'Savunmacı talep, geri ödeme ve sağlık turizmi döngüsü'
        Summary = 'Hastane ve sağlık hizmetleri talebi görece savunmacıdır. Kârlılık; fiyat tarifeleri, doktor ve personel maliyetleri, sağlık turizmi ve kapasite kullanımına bağlıdır.'
        Positive = 'Sağlık turizminin büyümesi; doluluk ve hasta başı gelirin artması; geri ödeme tarifelerinin iyileşmesi; yeni kapasitenin verimli kullanılması.'
        Negative = 'Personel maliyetlerinin hızlı artması; geri ödeme fiyatlarının maliyetlerin gerisinde kalması; döviz cinsi tıbbi malzeme baskısı; yeni yatırımların düşük dolulukla çalışması.'
        Indicators = 'Hasta sayısı, hasta başı gelir, yabancı hasta payı, doluluk, SGK ve özel sigorta tarifeleri, personel giderleri ve yatırım harcaması.'
        Note = 'Savunmacı talep, yanlış fiyatlama veya yüksek maliyet artışını tamamen telafi etmez.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Sağlık Teknolojisi'
        SectorEN = 'Health Technology'
        Cycle = 'Ar-Ge, ruhsat, ihracat ve ürün portföyü döngüsü'
        Summary = 'İlaç ve sağlık teknolojisi şirketlerinde ürün portföyü, ruhsat süreçleri, ihracat, kur etkisi ve Ar-Ge başarısı belirleyicidir.'
        Positive = 'Yeni ürün veya ruhsat; ihracat büyümesi; yüksek katma değerli ürün karması; kamu fiyat güncellemeleri; kapasite kullanımının artması.'
        Negative = 'Ruhsat gecikmesi; fiyat baskısı; döviz cinsi hammadde maliyetinin artması; patent veya rekabet riski; Ar-Ge harcamasının satışa dönüşmemesi.'
        Indicators = 'Ruhsat haberleri, ürün lansmanları, ihracat payı, ilaç fiyat kararnamesi, brüt marj, Ar-Ge giderleri ve kapasite kullanımı.'
        Note = 'Bu sektörde tek bir ürün veya ruhsat haberi şirket değerini sektör ortalamasından daha fazla etkileyebilir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Endüstriyel Hizmetler'
        SectorEN = 'Industrial Services'
        Cycle = 'Yatırım, altyapı ve sipariş döngüsü'
        Summary = 'Mühendislik, taahhüt ve endüstriyel hizmet şirketleri; kamu ve özel sektör yatırımlarına, sipariş birikimine ve proje kârlılığına duyarlıdır.'
        Positive = 'Altyapı ve sanayi yatırımlarının artması; yeni ihale ve sözleşmeler; güçlü sipariş birikimi; proje teslimatlarının hızlanması; maliyetlerin sözleşmelere yansıtılması.'
        Negative = 'Proje gecikmesi; maliyet aşımı; tahsilat riski; sabit fiyatlı sözleşmelerde enflasyon baskısı; yatırım iştahının düşmesi.'
        Indicators = 'Yeni sözleşmeler, sipariş birikimi, hakediş ve tahsilat, yatırım teşvikleri, kamu yatırım bütçesi, faaliyet marjı ve işletme sermayesi.'
        Note = 'Sipariş tutarı kadar siparişin marjı, süresi ve tahsil edilebilirliği de önemlidir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Çeşitli'
        SectorEN = 'Miscellaneous'
        Cycle = 'Şirket özelinde değişen karma döngü'
        Summary = 'Bu sınıfta ortak bir ekonomik sürücü zayıftır. Şirketin iştirak yapısı, varlık kalitesi, özel projeleri ve sermaye tahsis kararları daha belirleyici olabilir.'
        Positive = 'İştirak değerinin görünür hâle gelmesi; varlık satışı; temettü veya geri alım; borç azaltımı; yeni büyüme projesinin başarıyla devreye alınması.'
        Negative = 'Karmaşık yapı; holding iskontosunun artması; zayıf sermaye tahsisi; borçluluk; tek seferlik kârlara aşırı bağımlılık.'
        Indicators = 'Net aktif değer, iştirak sonuçları, varlık satışları, borçluluk, temettü politikası, geri alım ve şirket özelindeki KAP açıklamaları.'
        Note = 'Sektör karşılaştırmasından çok şirket bazlı değerleme ve dipnot analizi gerekir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Enerji Dışı Mineraller'
        SectorEN = 'Non-Energy Minerals'
        Cycle = 'Metal, çimento, inşaat ve küresel emtia döngüsü'
        Summary = 'Demir-çelik, çimento ve diğer mineral şirketlerinde emtia fiyatı, inşaat talebi, ihracat, enerji maliyeti ve kapasite kullanım oranı önemlidir.'
        Positive = 'Metal veya ürün fiyatlarının yükselmesi; Çin ve küresel talepte toparlanma; iç inşaat faaliyetinin canlanması; enerji maliyetlerinin gerilemesi; ihracat marjının artması.'
        Negative = 'Küresel arz fazlası; emtia fiyat düşüşü; yüksek enerji maliyeti; güçlü TL; düşük kapasite kullanımı; ithalat rekabeti.'
        Indicators = 'Çelik ve metal fiyatları, çimento satışları, inşaat güveni, Çin PMI, enerji fiyatları, kapasite kullanım oranı ve ton başı marj.'
        Note = 'Emtia şirketlerinde düşük F/K bazen döngünün tepe noktasındaki geçici yüksek kârı yansıtabilir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Süreç Endüstrileri'
        SectorEN = 'Process Industries'
        Cycle = 'Girdi-çıktı makası, enerji ve kapasite döngüsü'
        Summary = 'Kimya, petrokimya, kâğıt ve benzeri süreç endüstrilerinde kârın ana sürücüsü ürün fiyatı ile hammadde ve enerji maliyeti arasındaki makastır.'
        Positive = 'Ürün-hammadde marjının açılması; kapasite kullanımının artması; enerji maliyetinin düşmesi; talebin toparlanması; verimli yeni kapasite.'
        Negative = 'Hammadde fiyatının üründen hızlı artması; enerji şoku; küresel arz fazlası; düşük talep; plan dışı bakım duruşu.'
        Indicators = 'Ürün ve hammadde fiyatları, spread/makas göstergeleri, enerji fiyatları, kapasite kullanım oranı, bakım takvimi ve stok seviyesi.'
        Note = 'Ciro artışı, girdi-çıktı makası daralıyorsa kâra dönüşmeyebilir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Üretici İmalat'
        SectorEN = 'Producer Manufacturing'
        Cycle = 'Sanayi yatırımı, ihracat, PMI ve sipariş döngüsü'
        Summary = 'Makine, otomotiv yan sanayi ve sermaye malı üreticileri; yatırım iştahı, ihracat pazarları, siparişler ve kapasite kullanımına duyarlıdır.'
        Positive = 'PMI ve sanayi üretiminde toparlanma; ihracat siparişlerinin artması; yatırım teşvikleri; kapasite kullanımının yükselmesi; verimlilik kazancı.'
        Negative = 'Sanayi yavaşlaması; ihracat pazarlarında daralma; yüksek finansman maliyeti; hammadde ve işçilik baskısı; sipariş iptalleri.'
        Indicators = 'Türkiye ve Avrupa PMI, sanayi üretimi, ihracat, sipariş birikimi, kapasite kullanım oranı, yatırım teşvikleri ve faaliyet marjı.'
        Note = 'Bu hisseler ekonomik toparlanma verisi belirginleşmeden önce yeni sipariş beklentisiyle hareketlenebilir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Perakende Ticaret'
        SectorEN = 'Retail Trade'
        Cycle = 'Tüketim, enflasyon, mağaza büyümesi ve marj döngüsü'
        Summary = 'Perakendeciler nominal büyümeden faydalanabilir, ancak asıl kalite göstergesi reel hacim, benzer mağaza satışları, stok yönetimi ve marjdır.'
        Positive = 'Kart harcamaları ve tüketimin güçlü seyri; mağaza trafiğinin artması; özel markalı ürün payı; stok dönüşünün hızlanması; kira ve personel maliyetinin kontrolü.'
        Negative = 'Reel tüketimde yavaşlama; fiyat rekabeti; stok kaybı; yüksek kira ve ücret giderleri; hızlı mağaza açılışının verimsizliği.'
        Indicators = 'Kart harcamaları, perakende satış hacmi, benzer mağaza satışları, mağaza sayısı, brüt marj, stok gün sayısı ve tüketici güveni.'
        Note = 'Yüksek enflasyonda nominal ciro yanıltıcı olabilir; hacim ve marj birlikte izlenmelidir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Teknoloji Hizmetleri'
        SectorEN = 'Technology Services'
        Cycle = 'Dijitalleşme, tekrarlayan gelir ve değerleme faizi döngüsü'
        Summary = 'Yazılım ve teknoloji hizmetleri şirketlerinde tekrarlayan gelir, müşteri kazanımı, ihracat ve yüksek büyümenin sürdürülebilirliği önemlidir. Uzun vadeli nakit akışları nedeniyle değerlemeler faizlere duyarlı olabilir.'
        Positive = 'Tekrarlayan gelir payının yükselmesi; yeni müşteri ve sözleşmeler; ihracat büyümesi; yüksek brüt marj; faizlerin düşeceği beklentisi; güçlü nakit üretimi.'
        Negative = 'Büyümenin yavaşlaması; yüksek müşteri yoğunlaşması; ücret maliyetleri; tahsilat sorunu; yüksek değerleme; faizlerin uzun süre yüksek kalması.'
        Indicators = 'Tekrarlayan gelir, sözleşme değeri, müşteri sayısı, ihracat payı, brüt marj, çalışan başı gelir, nakit akışı ve piyasa faizleri.'
        Note = 'İyi şirket ile iyi fiyat aynı şey değildir; yüksek büyüme beklentisi zaten değerlemeye girmiş olabilir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Ulaştırma'
        SectorEN = 'Transportation'
        Cycle = 'Yolcu/yük talebi, yakıt, kur ve jeopolitik döngü'
        Summary = 'Havacılık, lojistik ve taşımacılık şirketleri; yolcu veya yük talebi, kapasite, bilet/navlun fiyatı, yakıt maliyeti ve kur hareketlerine duyarlıdır.'
        Positive = 'Yolcu veya yük talebinin artması; doluluk oranının yükselmesi; güçlü turizm sezonu; bilet veya navlun gelirinin maliyetlerden hızlı büyümesi; yakıt fiyatının gerilemesi.'
        Negative = 'Yakıt fiyatı şoku; jeopolitik risk; talep düşüşü; kapasite fazlası; operasyonel aksaklık; döviz cinsi borç baskısı.'
        Indicators = 'DHMİ yolcu verileri, turizm istatistikleri, kargo hacmi, doluluk, birim gelir, jet yakıtı/Brent, kapasite ve net borç.'
        Note = 'Ulaştırma hisseleri sezon başlamadan önce rezervasyon ve kapasite beklentilerini fiyatlayabilir.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Altyapı Hizmetleri'
        SectorEN = 'Utilities'
        Cycle = 'Regüle tarife, faiz, enerji girdisi ve temettü döngüsü'
        Summary = 'Elektrik, gaz ve diğer altyapı hizmetlerinde talep görece istikrarlıdır. Tarife düzenlemeleri, enerji girdileri, borçluluk ve yatırım finansmanı kârlılığı belirler.'
        Positive = 'Maliyetleri karşılayan tarife artışları; faizlerin gerilemesi; tahsilatın güçlü kalması; üretim veya dağıtım verimliliği; öngörülebilir temettü.'
        Negative = 'Tarifelerin maliyetlerin gerisinde kalması; yüksek borç ve faiz gideri; doğal gaz veya enerji maliyeti şoku; tahsilat bozulması; düzenleyici belirsizlik.'
        Indicators = 'EPDK tarifeleri, elektrik ve doğal gaz fiyatları, faizler, net borç/FAVÖK, tahsilat oranı, üretim hacmi ve yatırım programı.'
        Note = 'Savunmacı yapı fiyat riskini azaltabilir, ancak yüksek borçluluk faiz döngüsüne duyarlılığı artırır.'
    }
    [pscustomobject][ordered]@{
        SectorTR = 'Ticari Hizmetler'
        SectorEN = 'Commercial Services'
        Cycle = 'Ekonomik faaliyet, istihdam ve sözleşme yenileme döngüsü'
        Summary = 'İşletmelere hizmet veren şirketlerde müşteri bütçeleri, ekonomik faaliyet, sözleşme yenilemeleri ve personel maliyetleri önemlidir.'
        Positive = 'Şirketlerin dış kaynak kullanımını artırması; yeni uzun vadeli sözleşmeler; müşteri kaybının düşük kalması; verimlilik ve ölçek ekonomisi.'
        Negative = 'Müşteri bütçelerinin kısılması; sözleşme yenileme kaybı; ücret maliyetlerinin fiyatlara yansıtılamaması; yoğun müşteri bağımlılığı.'
        Indicators = 'Yeni sözleşmeler, yenileme oranı, müşteri yoğunlaşması, çalışan maliyeti, hizmet PMI ve faaliyet marjı.'
        Note = 'Sözleşme büyüklüğü kadar fiyat güncelleme mekanizması ve tahsilat kalitesi de incelenmelidir.'
    }
)

function Format-Number {
    param(
        $Value,
        [string]$Format = 'N2',
        [string]$Suffix = ''
    )

    if ($null -eq $Value) {
        return '-'
    }

    return [string]::Format($script:trCulture, "{0:$Format}$Suffix", [double]$Value)
}

function Get-ChartBrush {
    param([string]$Color)

    return [Windows.Media.BrushConverter]::new().ConvertFromString($Color)
}

function Add-CanvasText {
    param(
        $Canvas,
        [string]$Text,
        [double]$Left,
        [double]$Top,
        [double]$Width = 80,
        [double]$FontSize = 10,
        [string]$Color = '#64748B',
        [string]$Alignment = 'Center',
        [switch]$SemiBold
    )

    $label = New-Object Windows.Controls.TextBlock
    $label.Text = $Text
    $label.Width = $Width
    $label.FontSize = $FontSize
    $label.Foreground = Get-ChartBrush -Color $Color
    $label.TextAlignment = $Alignment
    $label.TextWrapping = 'Wrap'
    if ($SemiBold) {
        $label.FontWeight = [Windows.FontWeights]::SemiBold
    }
    [Windows.Controls.Canvas]::SetLeft($label, $Left)
    [Windows.Controls.Canvas]::SetTop($label, $Top)
    [void]$Canvas.Children.Add($label)
}

function Show-CanvasMessage {
    param(
        $Canvas,
        [string]$Message
    )

    [void]$Canvas.Children.Clear()
    $width = if ($Canvas.ActualWidth -gt 0) { $Canvas.ActualWidth } else { [double]$Canvas.Width }
    $height = if ($Canvas.ActualHeight -gt 0) { $Canvas.ActualHeight } else { [double]$Canvas.Height }
    Add-CanvasText -Canvas $Canvas -Text $Message -Left 15 -Top ([Math]::Max(20, ($height / 2) - 18)) -Width ([Math]::Max(100, $width - 30)) -FontSize 11
}

function Draw-BarChart {
    param(
        $Canvas,
        [object[]]$Rows,
        [string]$ValueProperty,
        [string]$Unit
    )

    [void]$Canvas.Children.Clear()
    $orderedRows = @($Rows)
    if ($orderedRows.Count -eq 0) {
        Show-CanvasMessage -Canvas $Canvas -Message 'Çeyreklik veri yok.'
        return
    }
    [array]::Reverse($orderedRows)

    $values = [System.Collections.Generic.List[double]]::new()
    foreach ($row in $orderedRows) {
        $property = $row.PSObject.Properties[$ValueProperty]
        if ($null -ne $property -and $null -ne $property.Value) {
            [void]$values.Add([double]$property.Value)
        }
    }
    if ($values.Count -eq 0) {
        Show-CanvasMessage -Canvas $Canvas -Message 'Grafik için veri yok.'
        return
    }

    $width = if ($Canvas.ActualWidth -gt 0) { $Canvas.ActualWidth } else { [double]$Canvas.Width }
    $height = if ($Canvas.ActualHeight -gt 0) { $Canvas.ActualHeight } else { [double]$Canvas.Height }
    $left = 38.0
    $right = 6.0
    $top = 12.0
    $bottom = 38.0
    $plotWidth = $width - $left - $right
    $plotHeight = $height - $top - $bottom

    $maxValue = [Math]::Max(0, [double](($values | Measure-Object -Maximum).Maximum))
    $minValue = [Math]::Min(0, [double](($values | Measure-Object -Minimum).Minimum))
    $range = $maxValue - $minValue
    if ($range -le 0) {
        $range = 1
    }
    $maxValue += $range * 0.08
    $minValue -= $range * 0.08
    $range = $maxValue - $minValue
    $zeroY = $top + (($maxValue / $range) * $plotHeight)

    $baseline = New-Object Windows.Shapes.Line
    $baseline.X1 = $left
    $baseline.X2 = $left + $plotWidth
    $baseline.Y1 = $zeroY
    $baseline.Y2 = $zeroY
    $baseline.Stroke = Get-ChartBrush -Color '#94A3B8'
    $baseline.StrokeThickness = 1
    [void]$Canvas.Children.Add($baseline)

    Add-CanvasText -Canvas $Canvas -Text (Format-Number -Value $maxValue -Format 'N1') -Left 0 -Top ($top - 6) -Width 34 -FontSize 9 -Alignment 'Right'
    Add-CanvasText -Canvas $Canvas -Text (Format-Number -Value $minValue -Format 'N1') -Left 0 -Top ($top + $plotHeight - 10) -Width 34 -FontSize 9 -Alignment 'Right'
    Add-CanvasText -Canvas $Canvas -Text $Unit -Left 0 -Top ($zeroY - 7) -Width 34 -FontSize 8 -Alignment 'Right'

    $groupWidth = $plotWidth / [Math]::Max(1, $orderedRows.Count)
    $barWidth = [Math]::Min(27, $groupWidth * 0.55)
    for ($index = 0; $index -lt $orderedRows.Count; $index++) {
        $row = $orderedRows[$index]
        $x = $left + ($index * $groupWidth) + (($groupWidth - $barWidth) / 2)
        $periodText = [string]$row.Period
        $property = $row.PSObject.Properties[$ValueProperty]
        $value = if ($null -ne $property) { $property.Value } else { $null }

        if ($null -ne $value) {
            $numericValue = [double]$value
            $valueY = $top + ((($maxValue - $numericValue) / $range) * $plotHeight)
            $barTop = [Math]::Min($zeroY, $valueY)
            $barHeight = [Math]::Max(1, [Math]::Abs($zeroY - $valueY))
            $bar = New-Object Windows.Shapes.Rectangle
            $bar.Width = $barWidth
            $bar.Height = $barHeight
            $bar.Fill = Get-ChartBrush -Color $(if ($numericValue -ge 0) { '#2563EB' } else { '#F97316' })
            [Windows.Controls.Canvas]::SetLeft($bar, $x)
            [Windows.Controls.Canvas]::SetTop($bar, $barTop)
            [void]$Canvas.Children.Add($bar)

            $valueLabelTop = if ($numericValue -ge 0) {
                [Math]::Max(0, $barTop - 15)
            }
            else {
                [Math]::Min($height - $bottom - 13, $barTop + $barHeight + 1)
            }
            Add-CanvasText -Canvas $Canvas -Text (Format-Number -Value $numericValue -Format 'N1') -Left ($left + ($index * $groupWidth)) -Top $valueLabelTop -Width $groupWidth -FontSize 8
        }
        else {
            Add-CanvasText -Canvas $Canvas -Text '-' -Left ($left + ($index * $groupWidth)) -Top ($zeroY - 7) -Width $groupWidth -FontSize 9
        }

        Add-CanvasText -Canvas $Canvas -Text $periodText -Left ($left + ($index * $groupWidth)) -Top ($height - 31) -Width $groupWidth -FontSize 8
    }
}

function Add-PieSlice {
    param(
        $Canvas,
        [double]$CenterX,
        [double]$CenterY,
        [double]$Radius,
        [double]$StartAngle,
        [double]$SweepAngle,
        [string]$Color
    )

    $startRadians = ($StartAngle - 90) * [Math]::PI / 180
    $endRadians = ($StartAngle + $SweepAngle - 90) * [Math]::PI / 180
    $startPoint = [Windows.Point]::new(
        $CenterX + ($Radius * [Math]::Cos($startRadians)),
        $CenterY + ($Radius * [Math]::Sin($startRadians))
    )
    $endPoint = [Windows.Point]::new(
        $CenterX + ($Radius * [Math]::Cos($endRadians)),
        $CenterY + ($Radius * [Math]::Sin($endRadians))
    )

    $figure = New-Object Windows.Media.PathFigure
    $figure.StartPoint = [Windows.Point]::new($CenterX, $CenterY)
    $figure.IsClosed = $true

    $firstLine = New-Object Windows.Media.LineSegment
    $firstLine.Point = $startPoint
    [void]$figure.Segments.Add($firstLine)

    $arc = New-Object Windows.Media.ArcSegment
    $arc.Point = $endPoint
    $arc.Size = [Windows.Size]::new($Radius, $Radius)
    $arc.SweepDirection = [Windows.Media.SweepDirection]::Clockwise
    $arc.IsLargeArc = $SweepAngle -gt 180
    [void]$figure.Segments.Add($arc)

    $lastLine = New-Object Windows.Media.LineSegment
    $lastLine.Point = [Windows.Point]::new($CenterX, $CenterY)
    [void]$figure.Segments.Add($lastLine)

    $geometry = New-Object Windows.Media.PathGeometry
    [void]$geometry.Figures.Add($figure)
    $path = New-Object Windows.Shapes.Path
    $path.Data = $geometry
    $path.Fill = Get-ChartBrush -Color $Color
    [void]$Canvas.Children.Add($path)
}

function Draw-ProfitSourceChart {
    param(
        $Canvas,
        $Stock
    )

    [void]$Canvas.Children.Clear()
    $components = @($Stock.ProfitSourceComponents)
    if ($components.Count -eq 0) {
        Show-CanvasMessage -Canvas $Canvas -Message 'Faaliyet kârı veya net kâr verisi bulunamadı.'
        return
    }

    $latestNetIncome = $Stock.LatestNetIncomeTRYBn
    if ($null -eq $latestNetIncome -or [double]$latestNetIncome -le 0) {
        $lines = @($components | ForEach-Object {
                '{0}: {1}' -f $_.Name, (Format-Number -Value $_.ValueTRYBn -Format 'N2' -Suffix ' Mr TL')
            })
        Show-CanvasMessage -Canvas $Canvas -Message ("Son çeyrek net zarar olduğu için pasta yüzdesi gösterilmez.`n" + ($lines -join "`n"))
        return
    }

    $positiveComponents = @($components | Where-Object { $null -ne $_.ValueTRY -and [double]$_.ValueTRY -gt 0 })
    if ($positiveComponents.Count -eq 0) {
        Show-CanvasMessage -Canvas $Canvas -Message 'Pozitif kâr katkısı bulunamadı.'
        return
    }

    $colors = @('#2563EB', '#F59E0B', '#8B5CF6', '#14B8A6')
    $totalPositive = [double](($positiveComponents | Measure-Object -Property ValueTRY -Sum).Sum)
    $centerX = 105.0
    $centerY = 102.0
    $radius = 78.0
    $startAngle = 0.0

    if ($positiveComponents.Count -eq 1) {
        $circle = New-Object Windows.Shapes.Ellipse
        $circle.Width = $radius * 2
        $circle.Height = $radius * 2
        $circle.Fill = Get-ChartBrush -Color $colors[0]
        [Windows.Controls.Canvas]::SetLeft($circle, $centerX - $radius)
        [Windows.Controls.Canvas]::SetTop($circle, $centerY - $radius)
        [void]$Canvas.Children.Add($circle)
    }
    else {
        for ($index = 0; $index -lt $positiveComponents.Count; $index++) {
            $component = $positiveComponents[$index]
            $sweepAngle = ([double]$component.ValueTRY / $totalPositive) * 360
            Add-PieSlice -Canvas $Canvas -CenterX $centerX -CenterY $centerY -Radius $radius -StartAngle $startAngle -SweepAngle $sweepAngle -Color $colors[$index % $colors.Count]
            $startAngle += $sweepAngle
        }
    }

    $hole = New-Object Windows.Shapes.Ellipse
    $hole.Width = 92
    $hole.Height = 92
    $hole.Fill = Get-ChartBrush -Color '#F8FAFC'
    [Windows.Controls.Canvas]::SetLeft($hole, $centerX - 46)
    [Windows.Controls.Canvas]::SetTop($hole, $centerY - 46)
    [void]$Canvas.Children.Add($hole)
    Add-CanvasText -Canvas $Canvas -Text 'Net kâr' -Left ($centerX - 43) -Top ($centerY - 20) -Width 86 -FontSize 10 -Color '#64748B'
    Add-CanvasText -Canvas $Canvas -Text (Format-Number -Value $latestNetIncome -Format 'N2' -Suffix ' Mr TL') -Left ($centerX - 48) -Top ($centerY - 2) -Width 96 -FontSize 11 -Color '#0F172A' -SemiBold

    $positiveColorIndex = 0
    for ($index = 0; $index -lt $components.Count; $index++) {
        $component = $components[$index]
        $isPositive = $null -ne $component.ValueTRY -and [double]$component.ValueTRY -gt 0
        $color = if ($isPositive) { $colors[$positiveColorIndex % $colors.Count] } else { '#F97316' }
        if ($isPositive) {
            $positiveColorIndex++
        }

        $legendMarker = New-Object Windows.Shapes.Rectangle
        $legendMarker.Width = 10
        $legendMarker.Height = 10
        $legendMarker.Fill = Get-ChartBrush -Color $color
        [Windows.Controls.Canvas]::SetLeft($legendMarker, 220)
        [Windows.Controls.Canvas]::SetTop($legendMarker, 35 + ($index * 68))
        [void]$Canvas.Children.Add($legendMarker)

        $shareText = if ($isPositive -and $null -ne $component.SharePct) {
            "pozitif katkıların %$([Math]::Round([double]$component.SharePct, 1))'i"
        }
        elseif ($component.IsNegativeAdjustment) {
            'negatif düzeltme'
        }
        else {
            'katkı yok'
        }
        $legendText = "{0}`n{1} | {2}" -f `
            $component.Name, `
            (Format-Number -Value $component.ValueTRYBn -Format 'N2' -Suffix ' Mr TL'), `
            $shareText
        Add-CanvasText -Canvas $Canvas -Text $legendText -Left 238 -Top (28 + ($index * 68)) -Width 280 -FontSize 10 -Color '#334155' -Alignment 'Left'
    }
}

function Update-SectorGuide {
    $guide = $listSectorCycles.SelectedItem
    if ($null -eq $guide) {
        $txtSectorGuideTitle.Text = 'Bir sektör seçin'
        $txtSectorGuideCycle.Text = ''
        $txtSectorGuideSummary.Text = ''
        $txtSectorGuidePositive.Text = ''
        $txtSectorGuideNegative.Text = ''
        $txtSectorGuideIndicators.Text = ''
        $txtSectorGuideNote.Text = ''
        return
    }

    $txtSectorGuideTitle.Text = "$($guide.SectorTR) | $($guide.SectorEN)"
    $txtSectorGuideCycle.Text = [string]$guide.Cycle
    $txtSectorGuideSummary.Text = [string]$guide.Summary
    $txtSectorGuidePositive.Text = [string]$guide.Positive
    $txtSectorGuideNegative.Text = [string]$guide.Negative
    $txtSectorGuideIndicators.Text = [string]$guide.Indicators
    $txtSectorGuideNote.Text = [string]$guide.Note
}

function Add-PortfolioDataGridColumn {
    param(
        $Grid,
        [string]$Header,
        [string]$Path,
        [double]$Width,
        [string]$StringFormat = ''
    )

    $column = New-Object Windows.Controls.DataGridTextColumn
    $column.Header = $Header
    $column.Width = [Windows.Controls.DataGridLength]::new($Width)
    $binding = New-Object Windows.Data.Binding $Path
    if (-not [string]::IsNullOrWhiteSpace($StringFormat)) {
        $binding.StringFormat = $StringFormat
    }
    $column.Binding = $binding
    [void]$Grid.Columns.Add($column)
}

function New-PortfolioDataGrid {
    $grid = New-Object Windows.Controls.DataGrid
    $grid.AutoGenerateColumns = $false
    $grid.IsReadOnly = $true
    $grid.HeadersVisibility = 'Column'
    $grid.GridLinesVisibility = 'Horizontal'
    $grid.HorizontalGridLinesBrush = Get-ChartBrush -Color '#EEF2F7'
    $grid.BorderBrush = Get-ChartBrush -Color '#E2E8F0'
    $grid.BorderThickness = [Windows.Thickness]::new(1)
    $grid.RowHeight = 28
    $grid.ColumnHeaderHeight = 31
    $grid.AlternatingRowBackground = Get-ChartBrush -Color '#F8FAFC'
    $grid.CanUserAddRows = $false
    $grid.CanUserDeleteRows = $false
    $grid.CanUserReorderColumns = $true
    $grid.CanUserResizeColumns = $true
    $grid.CanUserSortColumns = $true
    return $grid
}

function New-PortfolioMetricCard {
    param(
        [string]$Label,
        [string]$InitialText = '-'
    )

    $border = New-Object Windows.Controls.Border
    $border.Background = Get-ChartBrush -Color '#F8FAFC'
    $border.BorderBrush = Get-ChartBrush -Color '#E2E8F0'
    $border.BorderThickness = [Windows.Thickness]::new(1)
    $border.Padding = [Windows.Thickness]::new(10)
    $border.Margin = [Windows.Thickness]::new(4)

    $stack = New-Object Windows.Controls.StackPanel
    $labelText = New-Object Windows.Controls.TextBlock
    $labelText.Text = $Label
    $labelText.Foreground = Get-ChartBrush -Color '#64748B'
    $labelText.FontSize = 11
    [void]$stack.Children.Add($labelText)

    $valueText = New-Object Windows.Controls.TextBlock
    $valueText.Text = $InitialText
    $valueText.Foreground = Get-ChartBrush -Color '#0F172A'
    $valueText.FontSize = 16
    $valueText.FontWeight = [Windows.FontWeights]::SemiBold
    $valueText.Margin = [Windows.Thickness]::new(0, 3, 0, 0)
    $valueText.TextWrapping = 'Wrap'
    [void]$stack.Children.Add($valueText)

    $border.Child = $stack
    return [pscustomobject]@{
        Border = $border
        Value = $valueText
    }
}

function New-ModelPortfolioTab {
    param($Definition)

    $tabItem = New-Object Windows.Controls.TabItem
    $tabItem.Header = $Definition.Strategy

    $root = New-Object Windows.Controls.Grid
    $root.Margin = [Windows.Thickness]::new(10)
    foreach ($height in @('Auto', 'Auto', 'Auto', '230', 'Auto', '*')) {
        $row = New-Object Windows.Controls.RowDefinition
        $row.Height = [Windows.GridLength]::new(
            $(if ($height -eq '*') { 1 } elseif ($height -eq 'Auto') { 1 } else { [double]$height }),
            $(if ($height -eq '*') { [Windows.GridUnitType]::Star } elseif ($height -eq 'Auto') { [Windows.GridUnitType]::Auto } else { [Windows.GridUnitType]::Pixel })
        )
        [void]$root.RowDefinitions.Add($row)
    }

    $header = New-Object Windows.Controls.StackPanel
    $title = New-Object Windows.Controls.TextBlock
    $title.Text = $Definition.Name
    $title.Foreground = Get-ChartBrush -Color '#0F172A'
    $title.FontSize = 20
    $title.FontWeight = [Windows.FontWeights]::SemiBold
    [void]$header.Children.Add($title)
    $description = New-Object Windows.Controls.TextBlock
    $description.Text = $Definition.Description
    $description.Foreground = Get-ChartBrush -Color '#64748B'
    $description.FontSize = 11
    $description.TextWrapping = 'Wrap'
    $description.Margin = [Windows.Thickness]::new(0, 4, 0, 0)
    [void]$header.Children.Add($description)
    $status = New-Object Windows.Controls.TextBlock
    $status.Text = 'İlk canlı tarama bekleniyor.'
    $status.Foreground = Get-ChartBrush -Color '#2563EB'
    $status.FontSize = 11
    $status.TextWrapping = 'Wrap'
    $status.Margin = [Windows.Thickness]::new(0, 5, 0, 8)
    [void]$header.Children.Add($status)
    [Windows.Controls.Grid]::SetRow($header, 0)
    [void]$root.Children.Add($header)

    $metrics = New-Object Windows.Controls.Primitives.UniformGrid
    $metrics.Columns = 6
    $metrics.Margin = [Windows.Thickness]::new(-4, 0, -4, 8)
    $metricValue = New-PortfolioMetricCard -Label 'Güncel Değer'
    $metricGain = New-PortfolioMetricCard -Label 'Baştan Beri Kazanç'
    $metricReturn = New-PortfolioMetricCard -Label 'Baştan Beri Getiri'
    $metricStart = New-PortfolioMetricCard -Label 'Başlangıç'
    $metricLast = New-PortfolioMetricCard -Label 'Son İşlem'
    $metricNext = New-PortfolioMetricCard -Label 'Sonraki Planlı İşlem'
    foreach ($metric in @($metricValue, $metricGain, $metricReturn, $metricStart, $metricLast, $metricNext)) {
        [void]$metrics.Children.Add($metric.Border)
    }
    [Windows.Controls.Grid]::SetRow($metrics, 1)
    [void]$root.Children.Add($metrics)

    $holdingsTitle = New-Object Windows.Controls.TextBlock
    $holdingsTitle.Text = 'Portföydeki 5 Hisse'
    $holdingsTitle.Foreground = Get-ChartBrush -Color '#334155'
    $holdingsTitle.FontSize = 13
    $holdingsTitle.FontWeight = [Windows.FontWeights]::SemiBold
    $holdingsTitle.Margin = [Windows.Thickness]::new(0, 3, 0, 6)
    [Windows.Controls.Grid]::SetRow($holdingsTitle, 2)
    [void]$root.Children.Add($holdingsTitle)

    $holdingsGrid = New-PortfolioDataGrid
    Add-PortfolioDataGridColumn -Grid $holdingsGrid -Header 'Sembol' -Path 'Symbol' -Width 72
    Add-PortfolioDataGridColumn -Grid $holdingsGrid -Header 'Şirket' -Path 'Company' -Width 210
    Add-PortfolioDataGridColumn -Grid $holdingsGrid -Header 'Sektör' -Path 'SectorTR' -Width 140
    Add-PortfolioDataGridColumn -Grid $holdingsGrid -Header 'Ağırlık %' -Path 'WeightPct' -Width 78 -StringFormat '{0:N2}'
    Add-PortfolioDataGridColumn -Grid $holdingsGrid -Header 'Güncel Değer TL' -Path 'CurrentValueTL' -Width 110 -StringFormat '{0:N2}'
    Add-PortfolioDataGridColumn -Grid $holdingsGrid -Header 'Güncel Fiyat' -Path 'CurrentPrice' -Width 90 -StringFormat '{0:N4}'
    Add-PortfolioDataGridColumn -Grid $holdingsGrid -Header 'Teorik Adet' -Path 'Quantity' -Width 95 -StringFormat '{0:N6}'
    Add-PortfolioDataGridColumn -Grid $holdingsGrid -Header 'Son İşlemden K/Z TL' -Path 'GainSinceRebalanceTL' -Width 125 -StringFormat '{0:N2}'
    Add-PortfolioDataGridColumn -Grid $holdingsGrid -Header 'Son İşlemden K/Z %' -Path 'GainSinceRebalancePct' -Width 125 -StringFormat '{0:N2}'
    Add-PortfolioDataGridColumn -Grid $holdingsGrid -Header 'Strateji Skoru' -Path 'StrategyScore' -Width 95 -StringFormat '{0:N1}'
    Add-PortfolioDataGridColumn -Grid $holdingsGrid -Header 'Makro/Sektör' -Path 'MacroSectorScore' -Width 96 -StringFormat '{0:N1}'
    Add-PortfolioDataGridColumn -Grid $holdingsGrid -Header 'FD/FAVÖK' -Path 'EvEbitda' -Width 78 -StringFormat '{0:N2}'
    Add-PortfolioDataGridColumn -Grid $holdingsGrid -Header 'Seçim Gerekçesi' -Path 'SelectionReason' -Width 430
    [Windows.Controls.Grid]::SetRow($holdingsGrid, 3)
    [void]$root.Children.Add($holdingsGrid)

    $transactionsTitle = New-Object Windows.Controls.TextBlock
    $transactionsTitle.Text = 'İşlem ve Eşitleme Geçmişi'
    $transactionsTitle.Foreground = Get-ChartBrush -Color '#334155'
    $transactionsTitle.FontSize = 13
    $transactionsTitle.FontWeight = [Windows.FontWeights]::SemiBold
    $transactionsTitle.Margin = [Windows.Thickness]::new(0, 12, 0, 6)
    [Windows.Controls.Grid]::SetRow($transactionsTitle, 4)
    [void]$root.Children.Add($transactionsTitle)

    $transactionsGrid = New-PortfolioDataGrid
    Add-PortfolioDataGridColumn -Grid $transactionsGrid -Header 'Tarih' -Path 'ExecutionDateText' -Width 125
    Add-PortfolioDataGridColumn -Grid $transactionsGrid -Header 'İşlem' -Path 'Action' -Width 165
    Add-PortfolioDataGridColumn -Grid $transactionsGrid -Header 'Sembol' -Path 'Symbol' -Width 80
    Add-PortfolioDataGridColumn -Grid $transactionsGrid -Header 'Fiyat' -Path 'Price' -Width 85 -StringFormat '{0:N4}'
    Add-PortfolioDataGridColumn -Grid $transactionsGrid -Header 'Teorik Adet' -Path 'Quantity' -Width 95 -StringFormat '{0:N6}'
    Add-PortfolioDataGridColumn -Grid $transactionsGrid -Header 'İşlem Değeri TL' -Path 'AmountTL' -Width 120 -StringFormat '{0:N2}'
    Add-PortfolioDataGridColumn -Grid $transactionsGrid -Header 'Açıklama' -Path 'Note' -Width 620
    [Windows.Controls.Grid]::SetRow($transactionsGrid, 5)
    [void]$root.Children.Add($transactionsGrid)

    $tabItem.Content = $root
    [void]$tabModelPortfolios.Items.Add($tabItem)

    return [pscustomobject]@{
        TabItem = $tabItem
        Status = $status
        Value = $metricValue.Value
        Gain = $metricGain.Value
        Return = $metricReturn.Value
        Start = $metricStart.Value
        Last = $metricLast.Value
        Next = $metricNext.Value
        HoldingsGrid = $holdingsGrid
        TransactionsGrid = $transactionsGrid
    }
}

function Initialize-ModelPortfolioTabs {
    if ($script:portfolioUi.Count -gt 0) {
        return
    }

    foreach ($definition in Get-ModelPortfolioDefinitions) {
        $script:portfolioUi[$definition.Id] = New-ModelPortfolioTab -Definition $definition
    }
}

function Refresh-ModelPortfolioTabs {
    foreach ($definition in Get-ModelPortfolioDefinitions) {
        $ui = $script:portfolioUi[$definition.Id]
        if ($null -eq $ui) {
            continue
        }

        $portfolioMatches = if ($null -ne $script:modelPortfolioSet) {
            @($script:modelPortfolioSet.Portfolios | Where-Object Id -eq $definition.Id | Select-Object -First 1)
        }
        else {
            @()
        }
        $portfolioMatches = @($portfolioMatches)
        $portfolio = if ($portfolioMatches.Count -gt 0) { $portfolioMatches[0] } else { $null }

        if ($null -eq $portfolio) {
            $ui.Status.Text = 'İlk canlı tarama bekleniyor; portföy henüz kurulmadı.'
            foreach ($label in @($ui.Value, $ui.Gain, $ui.Return, $ui.Start, $ui.Last, $ui.Next)) {
                $label.Text = '-'
                $label.Foreground = $script:neutralBrush
            }
            $ui.HoldingsGrid.ItemsSource = $null
            $ui.TransactionsGrid.ItemsSource = $null
            continue
        }

        $ui.Status.Text = [string]$portfolio.StatusNote
        $ui.Value.Text = Format-Number -Value $portfolio.CurrentValueTL -Format 'N2' -Suffix ' TL'
        $ui.Gain.Text = Format-Number -Value $portfolio.TotalGainTL -Format 'N2' -Suffix ' TL'
        $ui.Return.Text = Format-Number -Value $portfolio.TotalReturnPct -Format 'N2' -Suffix '%'
        $ui.Start.Text = [string]$portfolio.StartDateText
        $ui.Last.Text = [string]$portfolio.LastRebalanceDateText
        $ui.Next.Text = if ([string]::IsNullOrWhiteSpace([string]$portfolio.NextRebalanceDate)) {
            '-'
        }
        else {
            ([datetime]$portfolio.NextRebalanceDate).ToString('dd.MM.yyyy')
        }
        $gainBrush = if ([double]$portfolio.TotalGainTL -gt 0) {
            $script:positiveBrush
        }
        elseif ([double]$portfolio.TotalGainTL -lt 0) {
            $script:negativeBrush
        }
        else {
            $script:neutralBrush
        }
        $ui.Gain.Foreground = $gainBrush
        $ui.Return.Foreground = $gainBrush
        $ui.HoldingsGrid.ItemsSource = @($portfolio.Holdings | Sort-Object Symbol)
        $ui.TransactionsGrid.ItemsSource = @($portfolio.Transactions | Sort-Object Sequence -Descending)
    }
}

function Save-ModelPortfolios {
    if ($null -eq $script:modelPortfolioSet) {
        return
    }

    try {
        $directory = Split-Path $script:portfolioPath -Parent
        if (-not (Test-Path $directory)) {
            [void](New-Item -ItemType Directory -Path $directory -Force)
        }
        $json = $script:modelPortfolioSet | ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText($script:portfolioPath, $json, [Text.UTF8Encoding]::new($true))
    }
    catch {
        $txtStatus.Text = "Model portföy kaydedilemedi: $($_.Exception.Message)"
    }
}

function Load-ModelPortfolios {
    if (-not (Test-Path $script:portfolioPath)) {
        Refresh-ModelPortfolioTabs
        return
    }

    try {
        $portfolioSet = Get-Content -Path $script:portfolioPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $portfolioSet.PSObject.Properties['Portfolios'] -or @($portfolioSet.Portfolios).Count -ne 4) {
            throw 'Model portföy dosyası beklenen dört portföyü içermiyor.'
        }
        $script:modelPortfolioSet = $portfolioSet
        Refresh-ModelPortfolioTabs
    }
    catch {
        $script:modelPortfolioSet = $null
        Refresh-ModelPortfolioTabs
        $txtStatus.Text = "Model portföy dosyası okunamadı: $($_.Exception.Message)"
    }
}

function Update-ModelPortfoliosFromStocks {
    param(
        [object[]]$Stocks,
        [switch]$AllowRebalance
    )

    if ($Stocks.Count -eq 0) {
        return
    }

    try {
        $updated = Update-ModelPortfolioSet `
            -PortfolioSet $script:modelPortfolioSet `
            -Stocks $Stocks `
            -AsOf (Get-Date) `
            -AllowRebalance:$AllowRebalance
        if ($null -ne $updated) {
            $script:modelPortfolioSet = $updated
            if ($AllowRebalance) {
                Save-ModelPortfolios
            }
        }
        Refresh-ModelPortfolioTabs
    }
    catch {
        $txtStatus.Text = "Model portföy güncellenemedi: $($_.Exception.Message)"
    }
}

function Get-SelectedStrategy {
    if ($null -eq $cmbStrategy.SelectedItem) {
        return 'Dengeli'
    }
    return [string]$cmbStrategy.SelectedItem.Content
}

function Set-BusyState {
    param(
        [bool]$IsBusy,
        [string]$Message
    )

    $btnScan.IsEnabled = -not $IsBusy
    $txtBusy.Visibility = if ($IsBusy) { 'Visible' } else { 'Collapsed' }
    $txtStatus.Text = $Message
}

function Save-Cache {
    param([object[]]$Stocks)

    try {
        $directory = Split-Path $script:cachePath -Parent
        if (-not (Test-Path $directory)) {
            [void](New-Item -ItemType Directory -Path $directory -Force)
        }

        $cache = [pscustomobject]@{
            UpdatedAt = (Get-Date).ToString('o')
            Count = $Stocks.Count
            Stocks = $Stocks
        }
        $json = $cache | ConvertTo-Json -Depth 6
        [IO.File]::WriteAllText($script:cachePath, $json, [Text.UTF8Encoding]::new($true))
    }
    catch {
        # Önbellek hatası canlı veriyi göstermeyi engellememeli.
    }
}

function Load-Cache {
    if (-not (Test-Path $script:cachePath)) {
        return
    }

    try {
        $cache = Get-Content -Path $script:cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $stocks = @($cache.Stocks)
        if ($stocks.Count -eq 0) {
            return
        }
        if ($null -eq $stocks[0].PSObject.Properties['QuarterlyFinancials'] -or
            $null -eq $stocks[0].PSObject.Properties['SectorTR'] -or
            $null -eq $stocks[0].PSObject.Properties['ProfitSourceComponents']) {
            $txtStatus.Text = 'Eski önbellek sürümü atlandı; canlı bilanço verisi bekleniyor.'
            return
        }

        $script:allStocks = $stocks
        $script:lastUpdated = [datetime]$cache.UpdatedAt
        $script:loadedFromCache = $true
        Update-ScoredStocks
        Update-ModelPortfoliosFromStocks -Stocks $stocks
        $txtStatus.Text = "Son kayıt gösteriliyor: $($stocks.Count) hisse | $($script:lastUpdated.ToString('dd.MM.yyyy HH:mm'))"
    }
    catch {
        $txtStatus.Text = 'Önbellek okunamadı; canlı veri bekleniyor.'
    }
}

function Update-Details {
    $stock = $gridStocks.SelectedItem
    if ($null -eq $stock) {
        $txtDetailSymbol.Text = 'Hisse seçin'
        $txtDetailCompany.Text = 'Puanın neden oluştuğunu burada görebilirsiniz.'
        $txtDetailPrice.Text = '-'
        $txtDetailChange.Text = '-'
        $txtDetailMarketCap.Text = '-'
        $txtDetailRisk.Text = '-'
        $txtDetailProfitTL.Text = '-'
        $txtDetailProfitUSD.Text = '-'
        $txtDetailEbitdaTL.Text = '-'
        $txtDetailEbitdaUSD.Text = '-'
        $txtDetailQuarter.Text = '-'
        $txtDetailUsdStrength.Text = '-'
        $txtDetailSector.Text = '-'
        $txtDetailIndustry.Text = '-'
        $gridQuarterly.ItemsSource = $null
        Show-CanvasMessage -Canvas $canvasProfitTL -Message 'Bir hisse seçin.'
        Show-CanvasMessage -Canvas $canvasProfitUSD -Message 'Bir hisse seçin.'
        Show-CanvasMessage -Canvas $canvasProfitSource -Message 'Bir hisse seçin.'
        $txtProfitSourceNote.Text = 'Bir hisse seçildiğinde kâr kaynağı açıklaması gösterilir.'
        $txtExplanation.Text = 'Canlı tarama tamamlandığında bir hisse seçin.'
        $btnOpenChart.IsEnabled = $false
        foreach ($bar in @($pbTrend, $pbValue, $pbQuality, $pbEarnings, $pbMomentum, $pbLiquidity, $pbMacroSector)) {
            $bar.Value = 0
        }
        foreach ($label in @($txtTrendScore, $txtValueScore, $txtQualityScore, $txtEarningsScore, $txtMomentumScore, $txtLiquidityScore, $txtMacroSectorScore)) {
            $label.Text = '-'
        }
        return
    }

    $reportDateText = if ($null -ne $stock.LatestReportDate) { ([datetime]$stock.LatestReportDate).ToString('dd.MM.yyyy') } else { 'veri yok' }
    $nextEarningsText = if ($null -ne $stock.NextEarningsDate) { ([datetime]$stock.NextEarningsDate).ToString('dd.MM.yyyy') } else { 'veri yok' }
    $confirmationLabel = if ($null -ne $stock.PSObject.Properties['ConfirmationLabel'] -and -not [string]::IsNullOrWhiteSpace([string]$stock.ConfirmationLabel)) {
        [string]$stock.ConfirmationLabel
    }
    else {
        'Teyit Verisi Yok'
    }
    $txtDetailSymbol.Text = "$($stock.Symbol)  |  $($stock.Signal)  $($stock.Score)  |  $confirmationLabel"
    $txtDetailCompany.Text = "$($stock.Company)`n$($stock.SectorTR) ($($stock.Sector)) | Alt sektör: $($stock.Industry) | Son açıklama: $reportDateText | Beklenen sonraki: $nextEarningsText"
    $txtDetailPrice.Text = (Format-Number -Value $stock.Price -Suffix ' TL')
    $txtDetailChange.Text = (Format-Number -Value $stock.ChangePct -Suffix '%')
    $txtDetailChange.Foreground = if ($null -eq $stock.ChangePct -or $stock.ChangePct -eq 0) {
        $script:neutralBrush
    }
    elseif ($stock.ChangePct -gt 0) {
        $script:positiveBrush
    }
    else {
        $script:negativeBrush
    }
    $txtDetailMarketCap.Text = (Format-Number -Value $stock.MarketCapBn -Format 'N1' -Suffix ' Mr TL')
    $txtDetailRisk.Text = [string]$stock.RiskLevel
    $txtDetailProfitTL.Text = (Format-Number -Value $stock.LatestNetIncomeTRYBn -Format 'N2' -Suffix ' Mr TL')
    $txtDetailProfitUSD.Text = (Format-Number -Value $stock.LatestNetIncomeUSDMn -Format 'N1' -Suffix ' Mn $')
    $txtDetailEbitdaTL.Text = (Format-Number -Value (Get-ObjectPropertyValue -Object $stock -Name 'LatestEbitdaTRYBn') -Format 'N2' -Suffix ' Mr TL')
    $txtDetailEbitdaUSD.Text = '{0} | FD/FAVÖK {1}' -f `
        (Format-Number -Value (Get-ObjectPropertyValue -Object $stock -Name 'LatestEbitdaUSDMn') -Format 'N1' -Suffix ' Mn $'), `
        (Format-Number -Value (Get-ObjectPropertyValue -Object $stock -Name 'EvEbitda') -Format 'N2')
    $txtDetailQuarter.Text = if ([string]::IsNullOrWhiteSpace([string]$stock.LatestQuarter)) { '-' } else { [string]$stock.LatestQuarter }
    $txtDetailUsdStrength.Text = [string]$stock.StrongUsdEarningsLabel
    $txtDetailUsdStrength.Foreground = if ($stock.StrongUsdEarnings) { $script:strongBrush } else { $script:neutralBrush }
    $txtDetailSector.Text = [string]$stock.SectorTR
    $txtDetailIndustry.Text = if ([string]::IsNullOrWhiteSpace([string]$stock.Industry)) { '-' } else { [string]$stock.Industry }
    $gridQuarterly.ItemsSource = @($stock.QuarterlyFinancials)
    Draw-BarChart -Canvas $canvasProfitTL -Rows @($stock.QuarterlyFinancials) -ValueProperty 'NetIncomeTRYBn' -Unit 'Mr TL'
    Draw-BarChart -Canvas $canvasProfitUSD -Rows @($stock.QuarterlyFinancials) -ValueProperty 'NetIncomeUSDMn' -Unit 'Mn $'
    Draw-ProfitSourceChart -Canvas $canvasProfitSource -Stock $stock
    $txtProfitSourceNote.Text = [string]$stock.ProfitSourceNote

    $pbTrend.Value = $stock.TrendScore
    $pbValue.Value = $stock.ValueScore
    $pbQuality.Value = $stock.QualityScore
    $pbEarnings.Value = $stock.EarningsScore
    $pbMomentum.Value = $stock.MomentumScore
    $pbLiquidity.Value = $stock.LiquidityScore
    $pbMacroSector.Value = $stock.MacroSectorScore
    $txtTrendScore.Text = [Math]::Round($stock.TrendScore).ToString()
    $txtValueScore.Text = [Math]::Round($stock.ValueScore).ToString()
    $txtQualityScore.Text = [Math]::Round($stock.QualityScore).ToString()
    $txtEarningsScore.Text = [Math]::Round($stock.EarningsScore).ToString()
    $txtMomentumScore.Text = [Math]::Round($stock.MomentumScore).ToString()
    $txtLiquidityScore.Text = [Math]::Round($stock.LiquidityScore).ToString()
    $txtMacroSectorScore.Text = [Math]::Round($stock.MacroSectorScore).ToString()
    $txtExplanation.Text = [string]$stock.Explanation
    $btnOpenChart.IsEnabled = $true
}

function Update-Grid {
    if ($script:scoredStocks.Count -eq 0) {
        $gridStocks.ItemsSource = $null
        Update-Details
        return
    }

    $selectedSymbol = if ($null -ne $gridStocks.SelectedItem) {
        [string]$gridStocks.SelectedItem.Symbol
    }
    else {
        ''
    }

    $search = $txtSearch.Text.Trim()
    $minimumScore = [double]$sldMinScore.Value
    $marketCapIndex = [Math]::Max(0, $cmbMarketCap.SelectedIndex)
    $minimumMarketCap = $script:marketCapFilters[$marketCapIndex]
    $includeHighRisk = $chkIncludeHighRisk.IsChecked -ne $false
    $strongUsdOnly = $chkStrongUsdOnly.IsChecked -eq $true

    $script:filteredStocks = @(
        $script:scoredStocks |
            Where-Object {
                $haystack = "$($_.Symbol) $($_.Company) $($_.SectorTR) $($_.Sector) $($_.Industry)"
                $matchesSearch = [string]::IsNullOrWhiteSpace($search) -or
                    $haystack.IndexOf($search, [StringComparison]::CurrentCultureIgnoreCase) -ge 0
                $matchesScore = $_.Score -ge $minimumScore
                $matchesMarketCap = $minimumMarketCap -eq 0 -or
                    ($null -ne $_.MarketCap -and $_.MarketCap -ge $minimumMarketCap)
                $matchesRisk = $includeHighRisk -or $_.RiskLevel -ne 'Yüksek'
                $matchesStrongUsd = -not $strongUsdOnly -or $_.StrongUsdEarnings
                $matchesSearch -and $matchesScore -and $matchesMarketCap -and $matchesRisk -and $matchesStrongUsd
            } |
            Sort-Object Score -Descending
    )

    $gridStocks.ItemsSource = $script:filteredStocks

    if ($script:filteredStocks.Count -gt 0) {
        $selection = $script:filteredStocks | Where-Object Symbol -eq $selectedSymbol | Select-Object -First 1
        if ($null -eq $selection) {
            $selection = $script:filteredStocks[0]
        }
        $gridStocks.SelectedItem = $selection
    }
    else {
        $gridStocks.SelectedItem = $null
        Update-Details
    }

    $updatedText = if ($null -ne $script:lastUpdated) {
        $script:lastUpdated.ToString('dd.MM.yyyy HH:mm')
    }
    else {
        'bilinmiyor'
    }
    $cacheText = if ($script:loadedFromCache) { ' | son kayıt' } else { '' }
    $txtStatus.Text = "$($script:filteredStocks.Count) / $($script:scoredStocks.Count) hisse gösteriliyor | Güncelleme: $updatedText$cacheText"
}

function Update-EntryOpportunityGrid {
    if ($script:entryOpportunities.Count -eq 0) {
        $gridEntryOpportunities.ItemsSource = $null
        return
    }

    $gridEntryOpportunities.ItemsSource = $script:entryOpportunities
}

function Remove-EntryOpportunityJob {
    if ($null -ne $script:entryOpportunityJob) {
        try {
            Remove-Job -Job $script:entryOpportunityJob -Force -ErrorAction SilentlyContinue
        }
        catch {
        }
        $script:entryOpportunityJob = $null
    }
}

function Start-EntryOpportunityRefresh {
    if ($script:scoredStocks.Count -eq 0) {
        $script:entryOpportunities = @()
        Update-EntryOpportunityGrid
        return
    }

    if ($null -ne $script:entryOpportunityJob) {
        Remove-EntryOpportunityJob
    }

    $gridEntryOpportunities.ItemsSource = $null
    $txtStatus.Text = 'Anlık giriş fırsatı radarı hesaplanıyor...'

    try {
        $stocksForEntry = @($script:scoredStocks)
        $script:entryOpportunityJob = Start-Job -InitializationScript {
            Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        } -ScriptBlock {
            param($Path, $Stocks)
            Import-Module $Path -Force -ErrorAction Stop
            Get-InstantEntryOpportunities -Stocks $Stocks -CandidateLimit 60 -TimeoutSec 5 -MaxElapsedSec 90
        } -ArgumentList $modulePath, $stocksForEntry
        $entryOpportunityTimer.Start()
    }
    catch {
        $script:entryOpportunities = @()
        Update-EntryOpportunityGrid
        $txtStatus.Text = "Anlık giriş radarı başlatılamadı: $($_.Exception.Message)"
        Remove-EntryOpportunityJob
    }
}

function Update-ScoredStocks {
    if ($script:allStocks.Count -eq 0) {
        return
    }

    $strategy = Get-SelectedStrategy
    $script:scoredStocks = @(Get-BistScores -Stocks $script:allStocks -Strategy $strategy)
    Update-Grid
    Start-EntryOpportunityRefresh
}

function Open-SelectedChart {
    $stock = $gridStocks.SelectedItem
    if ($null -eq $stock) {
        return
    }

    try {
        $symbol = [Uri]::EscapeDataString([string]$stock.TradingViewSymbol)
        Start-Process "https://www.tradingview.com/chart/?symbol=$symbol"
    }
    catch {
        [void][Windows.MessageBox]::Show(
            "Grafik açılamadı: $($_.Exception.Message)",
            'BIST Hisse Tarayıcı',
            'OK',
            'Warning'
        )
    }
}

function Get-QuarterField {
    param(
        $Stock,
        [int]$Index,
        [string]$Field
    )

    $quarters = @($Stock.QuarterlyFinancials)
    if ($Index -lt 0 -or $Index -ge $quarters.Count) {
        return $null
    }

    $property = $quarters[$Index].PSObject.Properties[$Field]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Export-VisibleStocks {
    if ($script:filteredStocks.Count -eq 0) {
        [void][Windows.MessageBox]::Show(
            'Dışa aktarılacak görünür hisse yok.',
            'BIST Hisse Tarayıcı',
            'OK',
            'Information'
        )
        return
    }

    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Title = 'BIST tarama sonucunu kaydet'
    $dialog.Filter = 'CSV dosyası (*.csv)|*.csv'
    $dialog.FileName = "bist_tarama_$((Get-Date).ToString('yyyyMMdd_HHmm')).csv"

    if ($dialog.ShowDialog() -ne $true) {
        return
    }

    try {
        $script:filteredStocks |
            Select-Object `
                @{ Name = 'Skor'; Expression = { $_.Score } },
                @{ Name = 'Görüş'; Expression = { $_.Signal } },
                @{ Name = 'Teyit Etiketi'; Expression = { $_.ConfirmationLabel } },
                @{ Name = 'Teyit Puanı'; Expression = { $_.ConfirmationScore } },
                @{ Name = 'Teknik Teyit'; Expression = { "$($_.TechnicalPassCount)/$($_.TechnicalCheckCount)" } },
                @{ Name = 'Kademeli Giriş Notu'; Expression = { $_.EntryNote } },
                @{ Name = 'Eksik Teyitler'; Expression = { $_.FailedConfirmations } },
                @{ Name = 'Sembol'; Expression = { $_.Symbol } },
                @{ Name = 'Şirket'; Expression = { $_.Company } },
                @{ Name = 'USD Güçlü Bilanço'; Expression = { $_.StrongUsdEarningsLabel } },
                @{ Name = 'Bilanço Puanı'; Expression = { $_.EarningsScore } },
                @{ Name = 'Son Finansal Dönem'; Expression = { $_.LatestQuarter } },
                @{ Name = 'Son Kâr Mr TL'; Expression = { $_.LatestNetIncomeTRYBn } },
                @{ Name = 'Son Kâr Mn USD'; Expression = { $_.LatestNetIncomeUSDMn } },
                @{ Name = 'Son FAVÖK Mr TL'; Expression = { $_.LatestEbitdaTRYBn } },
                @{ Name = 'Son FAVÖK Mn USD'; Expression = { $_.LatestEbitdaUSDMn } },
                @{ Name = 'FAVÖK USD Yıllık %'; Expression = { $_.EbitdaUsdYoYPct } },
                @{ Name = 'FAVÖK Trendi'; Expression = { $_.EbitdaTrendLabel } },
                @{ Name = 'Pozitif FAVÖK Çeyrek Sayısı'; Expression = { $_.PositiveEbitdaQuarterCount } },
                @{ Name = 'FD/FAVÖK'; Expression = { $_.EvEbitda } },
                @{ Name = 'Makro/Sektör Puanı'; Expression = { $_.MacroSectorScore } },
                @{ Name = 'BIST100 1Y %'; Expression = { $_.Bist100PerfYear } },
                @{ Name = 'Hisse-BIST100 1Y Puan'; Expression = { $_.StockVsBist1YPct } },
                @{ Name = 'Hisse-Enflasyon 1Y Puan'; Expression = { $_.StockVsInflation1YPct } },
                @{ Name = 'Sektör Rotasyonu'; Expression = { $_.SectorRotationLabel } },
                @{ Name = 'Sektör 3A %'; Expression = { $_.SectorIndexPerf3Month } },
                @{ Name = 'Sektör-BIST100 3A Puan'; Expression = { $_.SectorVsBist3Month } },
                @{ Name = 'Son Faaliyet Kârı Mr TL'; Expression = { $_.OperatingIncomeTRYBn } },
                @{ Name = 'Faaliyet Dışı Vergi Değerleme ve Diğer Mr TL'; Expression = { $_.OtherProfitContributionTRYBn } },
                @{ Name = 'Kâr USD Yıllık %'; Expression = { $_.NetIncomeUsdYoYPct } },
                @{ Name = 'Ciro USD Yıllık %'; Expression = { $_.RevenueUsdYoYPct } },
                @{ Name = 'Q0 Dönem'; Expression = { Get-QuarterField -Stock $_ -Index 0 -Field 'Period' } },
                @{ Name = 'Q0 Kâr Mr TL'; Expression = { Get-QuarterField -Stock $_ -Index 0 -Field 'NetIncomeTRYBn' } },
                @{ Name = 'Q0 Kâr Mn USD'; Expression = { Get-QuarterField -Stock $_ -Index 0 -Field 'NetIncomeUSDMn' } },
                @{ Name = 'Q0 FAVÖK Mr TL'; Expression = { Get-QuarterField -Stock $_ -Index 0 -Field 'EbitdaTRYBn' } },
                @{ Name = 'Q0 FAVÖK Mn USD'; Expression = { Get-QuarterField -Stock $_ -Index 0 -Field 'EbitdaUSDMn' } },
                @{ Name = 'Q1 Dönem'; Expression = { Get-QuarterField -Stock $_ -Index 1 -Field 'Period' } },
                @{ Name = 'Q1 Kâr Mr TL'; Expression = { Get-QuarterField -Stock $_ -Index 1 -Field 'NetIncomeTRYBn' } },
                @{ Name = 'Q1 Kâr Mn USD'; Expression = { Get-QuarterField -Stock $_ -Index 1 -Field 'NetIncomeUSDMn' } },
                @{ Name = 'Q1 FAVÖK Mr TL'; Expression = { Get-QuarterField -Stock $_ -Index 1 -Field 'EbitdaTRYBn' } },
                @{ Name = 'Q1 FAVÖK Mn USD'; Expression = { Get-QuarterField -Stock $_ -Index 1 -Field 'EbitdaUSDMn' } },
                @{ Name = 'Q2 Dönem'; Expression = { Get-QuarterField -Stock $_ -Index 2 -Field 'Period' } },
                @{ Name = 'Q2 Kâr Mr TL'; Expression = { Get-QuarterField -Stock $_ -Index 2 -Field 'NetIncomeTRYBn' } },
                @{ Name = 'Q2 Kâr Mn USD'; Expression = { Get-QuarterField -Stock $_ -Index 2 -Field 'NetIncomeUSDMn' } },
                @{ Name = 'Q2 FAVÖK Mr TL'; Expression = { Get-QuarterField -Stock $_ -Index 2 -Field 'EbitdaTRYBn' } },
                @{ Name = 'Q2 FAVÖK Mn USD'; Expression = { Get-QuarterField -Stock $_ -Index 2 -Field 'EbitdaUSDMn' } },
                @{ Name = 'Q3 Dönem'; Expression = { Get-QuarterField -Stock $_ -Index 3 -Field 'Period' } },
                @{ Name = 'Q3 Kâr Mr TL'; Expression = { Get-QuarterField -Stock $_ -Index 3 -Field 'NetIncomeTRYBn' } },
                @{ Name = 'Q3 Kâr Mn USD'; Expression = { Get-QuarterField -Stock $_ -Index 3 -Field 'NetIncomeUSDMn' } },
                @{ Name = 'Q3 FAVÖK Mr TL'; Expression = { Get-QuarterField -Stock $_ -Index 3 -Field 'EbitdaTRYBn' } },
                @{ Name = 'Q3 FAVÖK Mn USD'; Expression = { Get-QuarterField -Stock $_ -Index 3 -Field 'EbitdaUSDMn' } },
                @{ Name = 'Q4 Dönem'; Expression = { Get-QuarterField -Stock $_ -Index 4 -Field 'Period' } },
                @{ Name = 'Q4 Kâr Mr TL'; Expression = { Get-QuarterField -Stock $_ -Index 4 -Field 'NetIncomeTRYBn' } },
                @{ Name = 'Q4 Kâr Mn USD'; Expression = { Get-QuarterField -Stock $_ -Index 4 -Field 'NetIncomeUSDMn' } },
                @{ Name = 'Q4 FAVÖK Mr TL'; Expression = { Get-QuarterField -Stock $_ -Index 4 -Field 'EbitdaTRYBn' } },
                @{ Name = 'Q4 FAVÖK Mn USD'; Expression = { Get-QuarterField -Stock $_ -Index 4 -Field 'EbitdaUSDMn' } },
                @{ Name = 'Son Fiyat'; Expression = { $_.Price } },
                @{ Name = 'Günlük Değişim %'; Expression = { $_.ChangePct } },
                @{ Name = 'Piyasa Değeri Mr TL'; Expression = { $_.MarketCapBn } },
                @{ Name = 'Hacim Lot'; Expression = { $_.Volume } },
                @{ Name = 'Göreceli Hacim'; Expression = { $_.RelativeVolume } },
                @{ Name = 'F/K'; Expression = { $_.PE } },
                @{ Name = 'PD/DD'; Expression = { $_.PB } },
                @{ Name = 'ROE %'; Expression = { $_.ROE } },
                @{ Name = 'RSI'; Expression = { $_.RSI } },
                @{ Name = 'MACD'; Expression = { $_.MacdLine } },
                @{ Name = 'MACD Sinyal'; Expression = { $_.MacdSignal } },
                @{ Name = 'MACD Histogram'; Expression = { $_.MacdHistogram } },
                @{ Name = '1 Ay %'; Expression = { $_.PerfMonth } },
                @{ Name = '1 Yıl %'; Expression = { $_.PerfYear } },
                @{ Name = '3 Yıl %'; Expression = { $_.Perf3Year } },
                @{ Name = '5 Yıl %'; Expression = { $_.Perf5Year } },
                @{ Name = 'Risk'; Expression = { $_.RiskLevel } },
                @{ Name = 'Risk Bayrakları'; Expression = { $_.RiskFlags } },
                @{ Name = 'Sektör'; Expression = { $_.SectorTR } },
                @{ Name = 'Sektör (TradingView)'; Expression = { $_.Sector } },
                @{ Name = 'Alt Sektör (TradingView)'; Expression = { $_.Industry } },
                @{ Name = 'Kâr Kaynağı Notu'; Expression = { $_.ProfitSourceNote } },
                @{ Name = 'USD Bilanço Kriter Açıklaması'; Expression = { $_.UsdEarningsReason } },
                @{ Name = 'Açıklama'; Expression = { $_.Explanation } } |
            Export-Csv -Path $dialog.FileName -NoTypeInformation -Delimiter ';' -Encoding UTF8

        $txtStatus.Text = "CSV kaydedildi: $($dialog.FileName)"
    }
    catch {
        [void][Windows.MessageBox]::Show(
            "CSV kaydedilemedi: $($_.Exception.Message)",
            'BIST Hisse Tarayıcı',
            'OK',
            'Error'
        )
    }
}

function Remove-ScanJob {
    if ($null -ne $script:scanJob) {
        try {
            Remove-Job -Job $script:scanJob -Force -ErrorAction SilentlyContinue
        }
        catch {
        }
        $script:scanJob = $null
    }
}

function Get-NewReportCount {
    param(
        [object[]]$PreviousStocks,
        [object[]]$CurrentStocks
    )

    if ($PreviousStocks.Count -eq 0) {
        return 0
    }

    $previousPeriods = @{}
    foreach ($stock in $PreviousStocks) {
        if ($null -ne $stock.FiscalPeriodEnd) {
            $previousPeriods[[string]$stock.Symbol] = [datetime]$stock.FiscalPeriodEnd
        }
    }

    $count = 0
    foreach ($stock in $CurrentStocks) {
        $symbol = [string]$stock.Symbol
        if ($null -ne $stock.FiscalPeriodEnd -and
            $previousPeriods.ContainsKey($symbol) -and
            [datetime]$stock.FiscalPeriodEnd -gt $previousPeriods[$symbol]) {
            $count++
        }
    }

    return $count
}

function Start-LiveScan {
    if ($null -ne $script:scanJob) {
        return
    }

    Set-BusyState -IsBusy $true -Message 'Canlı BIST, bilanço ve TCMB kur verisi alınıyor...'

    try {
        $script:scanJob = Start-Job -InitializationScript {
            Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        } -ScriptBlock {
            param($Path)
            Import-Module $Path -Force -ErrorAction Stop
            Invoke-BistStockScan
        } -ArgumentList $modulePath
        $scanTimer.Start()
    }
    catch {
        Set-BusyState -IsBusy $false -Message "Tarama başlatılamadı: $($_.Exception.Message)"
        Remove-ScanJob
    }
}

$scanTimer = New-Object Windows.Threading.DispatcherTimer
$scanTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$scanTimer.Add_Tick({
    if ($null -eq $script:scanJob) {
        $scanTimer.Stop()
        return
    }

    $state = $script:scanJob.State.ToString()
    if ($state -eq 'Completed') {
        try {
            $stocks = @(Receive-Job -Job $script:scanJob -ErrorAction Stop)
            if ($stocks.Count -eq 0) {
                throw 'Tarama boş sonuç döndürdü.'
            }

            $newReportCount = Get-NewReportCount -PreviousStocks $script:allStocks -CurrentStocks $stocks
            $script:allStocks = $stocks
            $script:lastUpdated = Get-Date
            $script:loadedFromCache = $false
            Save-Cache -Stocks $stocks
            Update-ScoredStocks
            Update-ModelPortfoliosFromStocks -Stocks $stocks -AllowRebalance
            $newReportText = if ($newReportCount -gt 0) { " | $newReportCount yeni bilanço bulundu" } else { '' }
            Set-BusyState -IsBusy $false -Message "$($stocks.Count) BIST hissesi tarandı$newReportText | $($script:lastUpdated.ToString('dd.MM.yyyy HH:mm'))"
        }
        catch {
            Set-BusyState -IsBusy $false -Message "Canlı veri işlenemedi: $($_.Exception.Message)"
        }
        finally {
            $scanTimer.Stop()
            Remove-ScanJob
        }
    }
    elseif ($state -in @('Failed', 'Stopped', 'Disconnected')) {
        $reason = $script:scanJob.ChildJobs[0].JobStateInfo.Reason
        $message = if ($null -ne $reason) { $reason.Message } else { 'Bilinmeyen bağlantı hatası.' }
        Set-BusyState -IsBusy $false -Message "Canlı tarama başarısız: $message"
        $scanTimer.Stop()
        Remove-ScanJob
    }
})

$entryOpportunityTimer = New-Object Windows.Threading.DispatcherTimer
$entryOpportunityTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$entryOpportunityTimer.Add_Tick({
    if ($null -eq $script:entryOpportunityJob) {
        $entryOpportunityTimer.Stop()
        return
    }

    $state = $script:entryOpportunityJob.State.ToString()
    if ($state -eq 'Completed') {
        try {
            $script:entryOpportunities = @(Receive-Job -Job $script:entryOpportunityJob -ErrorAction Stop)
            Update-EntryOpportunityGrid
            $radarText = if ($script:entryOpportunities.Count -gt 0) {
                'Anlık giriş radarı: ' + (($script:entryOpportunities | ForEach-Object { "$($_.Symbol) $($_.EntryOpportunityScore)" }) -join ', ')
            }
            else {
                'Anlık giriş radarı bugün uygun aday bulamadı.'
            }
            $txtStatus.Text = $radarText
        }
        catch {
            $script:entryOpportunities = @()
            Update-EntryOpportunityGrid
            $txtStatus.Text = "Anlık giriş radarı hesaplanamadı: $($_.Exception.Message)"
        }
        finally {
            $entryOpportunityTimer.Stop()
            Remove-EntryOpportunityJob
        }
    }
    elseif ($state -in @('Failed', 'Stopped', 'Disconnected')) {
        $reason = $script:entryOpportunityJob.ChildJobs[0].JobStateInfo.Reason
        $message = if ($null -ne $reason) { $reason.Message } else { 'Bilinmeyen bağlantı hatası.' }
        $script:entryOpportunities = @()
        Update-EntryOpportunityGrid
        $txtStatus.Text = "Anlık giriş radarı başarısız: $message"
        $entryOpportunityTimer.Stop()
        Remove-EntryOpportunityJob
    }
})

$autoRefreshTimer = New-Object Windows.Threading.DispatcherTimer
$autoRefreshTimer.Interval = [TimeSpan]::FromMinutes(30)
$autoRefreshTimer.Add_Tick({
    Start-LiveScan
})

$btnScan.Add_Click({ Start-LiveScan })
$btnExport.Add_Click({ Export-VisibleStocks })
$btnOpenChart.Add_Click({ Open-SelectedChart })
$btnRefreshEntryOpportunities.Add_Click({ Start-EntryOpportunityRefresh })
$gridStocks.Add_MouseDoubleClick({ Open-SelectedChart })
$gridStocks.Add_SelectionChanged({ Update-Details })
$listSectorCycles.Add_SelectionChanged({ Update-SectorGuide })
$txtSearch.Add_TextChanged({ Update-Grid })
$cmbMarketCap.Add_SelectionChanged({ Update-Grid })
$chkIncludeHighRisk.Add_Click({ Update-Grid })
$chkStrongUsdOnly.Add_Click({ Update-Grid })
$sldMinScore.Add_ValueChanged({
    $txtMinScore.Text = [Math]::Round($sldMinScore.Value).ToString()
    Update-Grid
})
$cmbStrategy.Add_SelectionChanged({ Update-ScoredStocks })
$btnClearFilters.Add_Click({
    $txtSearch.Text = ''
    $cmbMarketCap.SelectedIndex = 0
    $sldMinScore.Value = 0
    $chkIncludeHighRisk.IsChecked = $true
    $chkStrongUsdOnly.IsChecked = $false
    Update-Grid
})

$listSectorCycles.ItemsSource = $script:sectorGuides
Initialize-ModelPortfolioTabs

$window.Add_Loaded({
    if ($listSectorCycles.SelectedIndex -lt 0 -and $script:sectorGuides.Count -gt 0) {
        $listSectorCycles.SelectedIndex = 0
    }
    Update-SectorGuide
    Update-Details
    Load-ModelPortfolios
    Load-Cache
    Start-LiveScan
    $autoRefreshTimer.Start()
})

$window.Add_Closing({
    $autoRefreshTimer.Stop()
    $entryOpportunityTimer.Stop()
    if ($null -ne $script:scanJob) {
        try {
            Stop-Job -Job $script:scanJob -ErrorAction SilentlyContinue
        }
        catch {
        }
        Remove-ScanJob
    }
    if ($null -ne $script:entryOpportunityJob) {
        try {
            Stop-Job -Job $script:entryOpportunityJob -ErrorAction SilentlyContinue
        }
        catch {
        }
        Remove-EntryOpportunityJob
    }
})

if ($ValidateOnly) {
    Write-Host 'Arayüz doğrulaması başarılı.'
    return
}

[void]$window.ShowDialog()
