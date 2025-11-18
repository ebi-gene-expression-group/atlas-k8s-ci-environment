#!/usr/bin/env python3
"""
Test script to use browser-use with EBI GXA website
"""

import asyncio
from browser_use import Agent, Browser, ChatBrowserUse

async def test_gxa_website():
    """Test the GXA website with browser-use"""
    
    # Initialize browser
    browser = Browser()
    
    # Initialize LLM (using ChatBrowserUse)
    llm = ChatBrowserUse()
    
    # Create agent with a simple task
    agent = Agent(
        task="Navigate to the EBI GXA website and find information about gene expression data",
        llm=llm,
        browser=browser,
    )
    
    print("Starting browser agent test on GXA website...")
    print("URL: http://wwwdev.ebi.ac.uk/gxa")
    
    try:
        # Run the agent
        history = await agent.run()
        
        print("\nAgent completed successfully!")
        print(f"Total actions taken: {len(history)}")
        
        # Print the last few actions for debugging
        for i, action in enumerate(history[-3:], 1):
            print(f"Action {i}: {action}")
            
    except Exception as e:
        print(f"Error occurred: {e}")
        return None
    
    return history

if __name__ == "__main__":
    print("Testing browser-use with EBI GXA website...")
    result = asyncio.run(test_gxa_website())
    
    if result:
        print("\nTest completed successfully!")
    else:
        print("\nTest failed!")

