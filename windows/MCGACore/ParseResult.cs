using System;
using System.Collections.Generic;

namespace MCGA.MCGACore
{
    public class ParseResult
    {
        public Guid Id { get; set; }
        public string ParserName { get; set; }
        public string Original { get; set; }
        public string Parsed { get; set; }
        public string? Details { get; set; }

        public ParseResult(string parserName, string original, string parsed, string? details = null, Guid? id = null)
        {
            Id = id ?? Guid.NewGuid();
            ParserName = parserName;
            Original = original;
            Parsed = parsed;
            Details = details;
        }
    }

    public class ParserInfo
    {
        public string Id => Name;
        public string Name { get; set; }
        public string ZhDescription { get; set; }
        public string EnDescription { get; set; }
        public List<ParserExample> Examples { get; set; }

        public ParserInfo(string name, string zhDescription, string enDescription, List<ParserExample> examples)
        {
            Name = name;
            ZhDescription = zhDescription;
            EnDescription = enDescription;
            Examples = examples;
        }
    }

    public class ParserExample
    {
        public string Id => Input;
        public string Input { get; set; }
        public string ZhExpected { get; set; }
        public string EnExpected { get; set; }

        public ParserExample(string input, string zhExpected, string enExpected)
        {
            Input = input;
            ZhExpected = zhExpected;
            EnExpected = enExpected;
        }
    }
}
