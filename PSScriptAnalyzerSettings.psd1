# PSScriptAnalyzer configuration — the PowerShell counterpart to .shellcheckrc.
@{
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # Wants a UTF-8 BOM on files containing non-ASCII characters. That rule
        # exists for Windows PowerShell 5.1, which misreads BOM-less UTF-8;
        # every script here declares #Requires -Version 7.0, and PowerShell 7
        # reads BOM-less UTF-8 correctly on every platform. A BOM would also
        # add a stray marker to diffs for no benefit.
        'PSUseBOMForUnicodeEncodedFile'
    )
}
