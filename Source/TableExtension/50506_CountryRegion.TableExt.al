tableextension 50506 CountryRegion extends "Country/Region"
{
    fields
    {
        field(50100; "Country Code for E-Invoicing"; Code[2])
        {
            DataClassification = ToBeClassified;
        }
    }

    var
        myInt: Integer;
}